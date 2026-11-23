import Foundation
import Testing
@testable import TokenBaseballCore

enum BasketballSample {
    /// 모든 선수의 능력이 `ability`인 팀.
    static func side(id: TeamID, ability: Double, tier: LeagueTier = .amateur, _ rng: inout SeededRNG) -> BasketballSide {
        var team = Team(id: id, name: "팀\(id) 농구단", city: "", tier: tier, isUser: false, season: 1)
        var players: [PlayerID: Player] = [:]
        for (index, position) in PlayerFactory.rosterPositions(tier, sport: .basketball).enumerated() {
            var spec = PlayerFactory.Spec(position: position, tier: tier, season: 1)
            spec.ability = ability...ability
            let player = PlayerFactory.make(id: id * 100 + index, spec: spec, &rng)
            players[player.id] = player
            team.roster.append(player.id)
        }
        return BasketballLineupBuilder.side(team: team, players: players)!
    }

    struct Stats {
        var games = 0, homeWins = 0, overtimes = 0, steps = 0
        var points = 0, threes = 0, threeTries = 0, shots = 0, made = 0
        var rebounds = 0, assists = 0, steals = 0, blocks = 0, turnovers = 0, fouls = 0, freeThrows = 0
        var starterSeconds = 0, benchSeconds = 0, topScorer = 0, fouledOut = 0
        func per(_ value: Int) -> Double { Double(value) / Double(games * 2) }
        var homeRate: Double { Double(homeWins) / Double(games) }
    }

    static func run(
        away: Double, home: Double, games: Int, rules: BasketballRules = BasketballRules(), seed: UInt64 = 7
    ) -> Stats {
        var rng = SeededRNG(seed: seed)
        var stats = Stats()
        for _ in 0..<games {
            let a = side(id: 1, ability: away, &rng)
            let h = side(id: 2, ability: home, &rng)
            var match = BasketballMatch(away: a, home: h, rules: rules, seed: rng.next())
            var steps = 0
            while !match.isFinished {
                match.step()
                steps += 1
                if steps > 3000 { break }
            }
            stats.games += 1
            stats.steps += steps
            if match.result == .homeWin { stats.homeWins += 1 }
            if match.wentToOvertime { stats.overtimes += 1 }
            for side in [match.home, match.away] {
                let total = side.totals
                stats.points += side.points
                stats.threes += total.threesMade
                stats.threeTries += total.threesAttempted
                stats.shots += total.fieldGoalsAttempted
                stats.made += total.fieldGoalsMade
                stats.rebounds += total.rebounds
                stats.assists += total.assists
                stats.steals += total.steals
                stats.blocks += total.blocks
                stats.turnovers += total.turnovers
                stats.fouls += total.fouls
                stats.freeThrows += total.freeThrowsAttempted
                stats.starterSeconds += side.players.filter(\.isStarter).reduce(0) { $0 + $1.line.seconds }
                stats.benchSeconds += side.players.filter { !$0.isStarter }.reduce(0) { $0 + $1.line.seconds }
                stats.topScorer += side.players.map(\.line.points).max() ?? 0
                stats.fouledOut += side.players.filter(\.fouledOut).count
            }
        }
        return stats
    }
}

@Suite struct BasketballEngineTests {
    @Test func 반드시_승부가_나고_기록이_맞아떨어진다() {
        var rng = SeededRNG(seed: 3)
        for _ in 0..<60 {
            let a = BasketballSample.side(id: 1, ability: 50, &rng)
            let h = BasketballSample.side(id: 2, ability: 50, &rng)
            var match = BasketballMatch(away: a, home: h, rules: BasketballRules(), seed: rng.next())
            match.runToEnd()
            #expect(match.isFinished)
            #expect(match.home.points != match.away.points)
            #expect(match.result != .draw && match.result != nil)
            for side in [match.home, match.away] {
                let total = side.totals
                // 팀 득점 = 선수 득점의 합 = 쿼터별 득점의 합 = 2점·3점·자유투로 넣은 점수.
                #expect(side.points == total.points)
                #expect(side.points == side.pointsByPeriod.reduce(0, +))
                #expect(total.points == (total.fieldGoalsMade - total.threesMade) * 2 + total.threesMade * 3 + total.freeThrowsMade)
                #expect(total.fieldGoalsMade <= total.fieldGoalsAttempted && total.threesMade <= total.threesAttempted)
                // 코트에는 늘 다섯 명이 있다: 뛴 시간의 합 = 경기 시간 × 5.
                #expect(side.players.filter(\.isOnCourt).count == 5)
                #expect(total.seconds == match.elapsed * 5)
                #expect(side.players.allSatisfy { $0.line.fouls <= BasketballMatch.foulLimit })
                // 5반칙으로 물러난 선수는 코트에 남아 있지 않다.
                #expect(side.players.allSatisfy { !($0.fouledOut && $0.isOnCourt) })
                #expect(side.players.filter(\.hasPlayed).allSatisfy { $0.line.games == 1 })
            }
            #expect(match.home.pointsByPeriod.count == match.away.pointsByPeriod.count)
            #expect(match.elapsed >= 40 * 60)
        }
    }

    @Test func 득점과_기록이_실제_농구와_비슷하다() {
        let stats = BasketballSample.run(away: 60, home: 60, games: 300)
        print("BASKET 60: 득점 \(stats.per(stats.points)) 야투 \(Double(stats.made) / Double(stats.shots)) 3점 \(Double(stats.threes) / Double(stats.threeTries)) (시도 \(stats.per(stats.threeTries))) 리바 \(stats.per(stats.rebounds)) 도움 \(stats.per(stats.assists)) 스틸 \(stats.per(stats.steals)) 블록 \(stats.per(stats.blocks)) 실책 \(stats.per(stats.turnovers)) 반칙 \(stats.per(stats.fouls)) 자유투 \(stats.per(stats.freeThrows)) 홈승 \(stats.homeRate) 연장 \(Double(stats.overtimes) / Double(stats.games)) 틱 \(stats.steps / stats.games) 주전분 \(Double(stats.starterSeconds) / 60 / Double(stats.games * 10)) 벤치분 \(Double(stats.benchSeconds) / 60 / Double(stats.games * 2)) 최다득점 \(stats.per(stats.topScorer)) 퇴장 \(stats.per(stats.fouledOut))")
        #expect((68...92).contains(stats.per(stats.points)))
        #expect((0.40...0.50).contains(Double(stats.made) / Double(stats.shots)))
        #expect((0.28...0.40).contains(Double(stats.threes) / Double(stats.threeTries)))
        #expect((30...44).contains(stats.per(stats.rebounds)))
        #expect((12...24).contains(stats.per(stats.assists)))
        #expect((8...16).contains(stats.per(stats.turnovers)))
        #expect((0.52...0.66).contains(stats.homeRate))
        #expect(Double(stats.overtimes) / Double(stats.games) < 0.12)
        // 한 경기는 300틱쯤 (1배속으로 15분).
        #expect((295...330).contains(stats.steps / stats.games))
        // 주전은 25~33분, 벤치도 뛴다.
        #expect((24.0...34.0).contains(Double(stats.starterSeconds) / 60 / Double(stats.games * 10)))
        #expect(stats.benchSeconds > 0)
    }

    @Test func 리그가_낮으면_점수가_덜_나고_강한_팀이_이긴다() {
        let low = BasketballSample.run(away: 25, home: 25, games: 200)
        let high = BasketballSample.run(away: 85, home: 85, games: 200)
        print("BASKET 25: \(low.per(low.points)) / 85: \(high.per(high.points))")
        #expect(low.per(low.points) < high.per(high.points) - 8)
        #expect((50...75).contains(low.per(low.points)))
        let mismatch = BasketballSample.run(away: 50, home: 60, games: 200)
        let slight = BasketballSample.run(away: 57, home: 60, games: 300, rules: {
            var rules = BasketballRules()
            rules.neutral = true
            return rules
        }())
        print("BASKET 50v60 홈승 \(mismatch.homeRate), 57v60 중립 \(slight.homeRate)")
        #expect(mismatch.homeRate > 0.85)
        #expect((0.58...0.80).contains(slight.homeRate))
    }

    @Test func 같은_시드면_같은_경기이고_저장했다가_이어도_같다() throws {
        var rng = SeededRNG(seed: 5)
        let a = BasketballSample.side(id: 1, ability: 55, &rng)
        let h = BasketballSample.side(id: 2, ability: 55, &rng)
        var one = BasketballMatch(away: a, home: h, rules: BasketballRules(), seed: 99)
        var two = BasketballMatch(away: a, home: h, rules: BasketballRules(), seed: 99)
        for _ in 0..<120 { one.step() }
        for _ in 0..<120 { two.step() }
        #expect(one == two)
        let data = try JSONEncoder().encode(one)
        var restored = try JSONDecoder().decode(BasketballMatch.self, from: data)
        #expect(restored == one)
        one.runToEnd()
        restored.runToEnd()
        #expect(restored == one)
        #expect(one.log.count <= 80)
    }

    @Test func 다섯_번째_반칙이면_내_선수라도_곧바로_물러난다() {
        var rng = SeededRNG(seed: 13)
        let a = BasketballSample.side(id: 1, ability: 50, &rng)
        var h = BasketballSample.side(id: 2, ability: 50, &rng)
        // 벤치에서 시작해 출전 시간을 보장받는 선수가 코트에 있다가 퇴장당한 상황.
        let mine = h.players.count - 1
        h.featured = h.players[mine].playerID
        h.featuredMinutes = 24
        BasketballMatch.swap(&h, out: 0, in: mine)
        h.players[mine].fouledOut = true
        h.players[mine].line.fouls = BasketballMatch.foulLimit
        var match = BasketballMatch(away: a, home: h, rules: BasketballRules(), seed: 1)
        var events: [MatchEvent] = []
        match.substitute(&events)
        #expect(match.home.players[mine].isOnCourt == false)
        #expect(match.home.players.filter(\.isOnCourt).count == 5)
        match.runToEnd()
        #expect(match.home.players[mine].isOnCourt == false)
        #expect(match.home.players[mine].line.seconds == 0)
    }

    @Test func 벤치에서_시작한_내_선수는_정해진_시간만큼_뛴다() {
        var rng = SeededRNG(seed: 11)
        for target in [8, 16, 24] {
            var total = 0
            let games = 30
            for _ in 0..<games {
                let a = BasketballSample.side(id: 1, ability: 50, &rng)
                var h = BasketballSample.side(id: 2, ability: 50, &rng)
                let mine = h.players.last!
                #expect(!mine.isStarter)
                h.featured = mine.playerID
                h.featuredMinutes = target
                var match = BasketballMatch(away: a, home: h, rules: BasketballRules(), seed: rng.next())
                match.runToEnd()
                let line = match.home.players.first { $0.playerID == mine.playerID }!.line
                #expect(line.games == 1)
                total += line.seconds
            }
            let minutes = Double(total) / 60 / Double(games)
            print("BASKET 목표 \(target)분 → \(minutes)분")
            #expect(abs(minutes - Double(target)) < 4)
        }
    }
}
