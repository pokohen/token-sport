import Foundation
import Testing
@testable import TokenBaseballCore

/// 테스트용 팀 만들기.
enum TestTeams {
    /// 모든 선수의 능력이 `ability` 근처인 팀.
    static func make(
        id: TeamID, tier: LeagueTier = .amateur, ability: Double, seed: UInt64
    ) -> (team: Team, players: [PlayerID: Player]) {
        var rng = SeededRNG(seed: seed)
        var team = Team(id: id, name: "팀\(id) 테스트", city: "", tier: tier, isUser: false, season: 1)
        var players: [PlayerID: Player] = [:]
        for (offset, position) in PlayerFactory.rosterPositions(tier, sport: .baseball).enumerated() {
            var spec = PlayerFactory.Spec(position: position, tier: tier, season: 1)
            spec.ability = ability...ability
            var player = PlayerFactory.make(id: id * 1000 + offset, spec: spec, &rng)
            player.teamID = id
            player.traits = []
            players[player.id] = player
            team.roster.append(player.id)
        }
        return (team, players)
    }

    static func match(
        awayAbility: Double, homeAbility: Double, tier: LeagueTier = .amateur,
        rules: MatchRules = MatchRules(homeEdge: 0), seed: UInt64
    ) -> MatchState {
        let away = make(id: 1, tier: tier, ability: awayAbility, seed: seed &+ 11)
        let home = make(id: 2, tier: tier, ability: homeAbility, seed: seed &+ 23)
        return MatchState(
            away: LineupBuilder.matchTeam(team: away.team, players: away.players)!,
            home: LineupBuilder.matchTeam(team: home.team, players: home.players)!,
            rules: rules, seed: seed)
    }
}

@Suite struct MatchEngineTests {
    struct Sample {
        var games = 0
        var pitches = 0, runs = 0, hits = 0, homeRuns = 0, walks = 0, strikeouts = 0, plateAppearances = 0
        var homeWins = 0, awayWins = 0, draws = 0, errors = 0

        var pitchesPerGame: Double { Double(pitches) / Double(games) }
        var runsPerTeam: Double { Double(runs) / Double(games * 2) }
    }

    static func sample(away: Double, home: Double, tier: LeagueTier = .amateur, games: Int, edge: Double = 0) -> Sample {
        var sample = Sample()
        for index in 0..<games {
            var match = TestTeams.match(
                awayAbility: away, homeAbility: home, tier: tier,
                rules: MatchRules(homeEdge: edge), seed: UInt64(index) &* 7919 &+ 1)
            match.runToEnd()
            sample.games += 1
            sample.pitches += match.pitchCount
            sample.runs += match.away.runs + match.home.runs
            sample.hits += match.away.hits + match.home.hits
            sample.errors += match.away.errors + match.home.errors
            for team in [match.away, match.home] {
                for batter in team.batters {
                    sample.homeRuns += batter.line.homeRuns
                    sample.walks += batter.line.walks
                    sample.strikeouts += batter.line.strikeouts
                    sample.plateAppearances += batter.line.plateAppearances
                }
            }
            switch match.result {
            case .homeWin: sample.homeWins += 1
            case .awayWin: sample.awayWins += 1
            default: sample.draws += 1
            }
        }
        return sample
    }

    @Test(arguments: [(25.0, LeagueTier.citizenAmateur), (50.0, .amateur), (82.0, .pro)])
    func 한_경기_수치가_야구답다(ability: Double, tier: LeagueTier) {
        let sample = Self.sample(away: ability, home: ability, tier: tier, games: 400)
        let pa = Double(sample.plateAppearances)
        print("""
        [능력 \(Int(ability))] 투구 \(Int(sample.pitchesPerGame))구, 팀당 \(String(format: "%.2f", sample.runsPerTeam))점, \
        안타 \(String(format: "%.1f", Double(sample.hits) / Double(sample.games * 2))), \
        홈런 \(String(format: "%.2f", Double(sample.homeRuns) / Double(sample.games * 2))), \
        볼넷 \(String(format: "%.1f%%", Double(sample.walks) / pa * 100)), \
        삼진 \(String(format: "%.1f%%", Double(sample.strikeouts) / pa * 100)), \
        실책 \(String(format: "%.2f", Double(sample.errors) / Double(sample.games * 2))), \
        홈 \(sample.homeWins) 원정 \(sample.awayWins) 무 \(sample.draws)
        """)
        #expect((240...330).contains(sample.pitchesPerGame))
        #expect((3.0...7.5).contains(sample.runsPerTeam))
        #expect(Double(sample.draws) / Double(sample.games) < 0.12)
    }

    @Test func 강한_팀이_더_자주_이기지만_늘_이기지는_않는다() {
        let sample = Self.sample(away: 40, home: 50, games: 400)
        let homeRate = Double(sample.homeWins) / Double(sample.games - sample.draws)
        print("[40 대 50] 강팀 승률 \(String(format: "%.3f", homeRate))")
        #expect(homeRate > 0.6)
        #expect(homeRate < 0.95)
    }

    @Test func 홈_보정이_있으면_홈팀이_조금_더_이긴다() {
        let neutral = Self.sample(away: 50, home: 50, games: 600)
        let boosted = Self.sample(away: 50, home: 50, games: 600, edge: 0.05)
        #expect(boosted.homeWins > neutral.homeWins)
    }

    @Test func 같은_시드면_문자_중계가_똑같다() {
        var first = TestTeams.match(awayAbility: 45, homeAbility: 50, seed: 42)
        var second = TestTeams.match(awayAbility: 45, homeAbility: 50, seed: 42)
        var firstLog: [MatchEvent] = []
        var secondLog: [MatchEvent] = []
        while !first.isFinished { firstLog += first.step() }
        while !second.isFinished { secondLog += second.step() }

        #expect(firstLog == secondLog)
        #expect(first == second)

        var other = TestTeams.match(awayAbility: 45, homeAbility: 50, seed: 43)
        other.runToEnd()
        #expect(other != first)
    }

    @Test func 저장했다_읽어도_똑같이_이어진다() throws {
        var original = TestTeams.match(awayAbility: 50, homeAbility: 50, seed: 7)
        for _ in 0..<120 { original.step() }

        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(MatchState.self, from: data)
        original.runToEnd()
        restored.runToEnd()

        #expect(original == restored)
    }

    /// 여러 경기를 돌려 조건에 맞는 경기를 찾는다.
    static func find(
        rules: MatchRules = MatchRules(homeEdge: 0), away: Double = 50, home: Double = 50,
        tier: LeagueTier = .amateur, where predicate: (MatchState) -> Bool
    ) -> MatchState? {
        for seed in 1...3000 {
            var match = TestTeams.match(
                awayAbility: away, homeAbility: home, tier: tier, rules: rules, seed: UInt64(seed))
            match.runToEnd()
            if predicate(match) { return match }
        }
        return nil
    }

    @Test func 홈팀이_앞서면_9회말을_하지_않는다() throws {
        let match = try #require(Self.find { $0.result == .homeWin && $0.inning == 9 && !$0.isBottom })
        #expect(match.home.runsByInning.count == 8)
        #expect(match.away.runsByInning.count == 9)
    }

    @Test func 끝내기는_홈팀이_앞서는_순간_끝난다() throws {
        let match = try #require(Self.find {
            $0.result == .homeWin && $0.isBottom && $0.inning >= 9 && $0.outs < 3
                && $0.log.contains { $0.text.hasPrefix("끝내기") }
        })
        #expect(match.home.runs > match.away.runs)
        #expect(match.home.runsByInning.count == match.inning)
    }

    @Test func 연장_11회까지_동점이면_무승부다() throws {
        let match = try #require(Self.find { $0.result == .draw })
        #expect(match.inning == 11)
        #expect(match.isBottom)
        #expect(match.home.runs == match.away.runs)

        // 어떤 경기도 11회를 넘기지 않는다.
        #expect(Self.find { $0.inning > 11 } == nil)
    }

    @Test func 승강_플레이오프는_승부가_날_때까지_한다() {
        #expect(Self.find(rules: MatchRules(maxInnings: nil, homeEdge: 0)) { $0.result == .draw } == nil)
        #expect(Self.find(rules: MatchRules(maxInnings: nil, homeEdge: 0)) { $0.inning > 11 } != nil)
    }

    @Test func 콜드게임은_켰을_때만_나온다() throws {
        let cold = MatchRules(coldGame: true, homeEdge: 0)
        let early = try #require(Self.find(rules: cold, away: 20, home: 45, tier: .citizenAmateur) {
            $0.inning < 9
        })
        let lead = abs(early.home.runs - early.away.runs)
        #expect(early.inning >= 5)
        #expect(lead >= (early.inning >= 7 ? 7 : 10))

        #expect(Self.find(away: 20, home: 45, tier: .citizenAmateur) { $0.inning < 9 } == nil)
    }

    @Test func 말_공격_중에_콜드게임_점수_차가_되면_그_자리에서_끝난다() {
        let cold = MatchRules(coldGame: true, homeEdge: 0)
        var endedMidInning = 0
        for seed in 1...300 {
            var match = TestTeams.match(
                awayAbility: 20, homeAbility: 45, tier: .citizenAmateur, rules: cold, seed: UInt64(seed))
            while !match.isFinished {
                match.step()
                guard !match.isFinished, match.isBottom else { continue }
                let lead = match.home.runs - match.away.runs
                // 홈팀이 이미 기준을 넘겼는데 말 공격이 이어지면 안 된다.
                #expect(!(match.inning >= 7 && lead >= 7), "시드 \(seed) \(match.inningLabel) \(lead)점 차")
                #expect(!(match.inning >= 5 && lead >= 10), "시드 \(seed) \(match.inningLabel) \(lead)점 차")
            }
            if match.inning < 9, match.isBottom, match.outs < 3 { endedMidInning += 1 }
        }
        #expect(endedMidInning > 0)
    }

    @Test func 기록이_서로_맞아떨어진다() {
        for seed in 1...200 {
            var match = TestTeams.match(awayAbility: 48, homeAbility: 52, seed: UInt64(seed))
            match.runToEnd()
            for (offense, defense) in [(match.away, match.home), (match.home, match.away)] {
                // 타자들이 낸 득점 = 팀 득점 = 상대 투수들의 실점
                #expect(offense.batters.reduce(0) { $0 + $1.line.runs } == offense.runs)
                #expect(defense.pitchers.reduce(0) { $0 + $1.line.runs } == offense.runs)
                #expect(offense.batters.reduce(0) { $0 + $1.line.hits } == offense.hits)
                #expect(defense.pitchers.reduce(0) { $0 + $1.line.hits } == offense.hits)
            }
            let wins = (match.away.pitchers + match.home.pitchers).reduce(0) { $0 + $1.line.wins }
            let losses = (match.away.pitchers + match.home.pitchers).reduce(0) { $0 + $1.line.losses }
            #expect(wins == (match.result == .draw ? 0 : 1))
            #expect(losses == wins)
        }
    }
}
