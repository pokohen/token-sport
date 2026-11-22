import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct BasketballCareerTests {
    @Test(arguments: Position.basketball)
    func 농구_선수로_6부_구단에_입단한다(position: Position) throws {
        let game = TestCareer.make(position)
        let me = try #require(game.myPlayer)
        #expect(game.sport == .basketball)
        #expect(game.teams.count == 60)
        #expect(Set(game.teams.map(\.name)).count == 60)
        #expect(game.teams.allSatisfy { $0.name.contains("농구") || NameGenerator.basketballProTeams.map(\.name).contains($0.name) })
        #expect(me.position == position && me.age == 16)
        #expect(game.userTier == .citizenAmateur)
        #expect(game.roundsPerSeason == 36)
        for team in game.teams {
            let roster = game.roster(of: team.id)
            #expect(roster.allSatisfy { $0.position.sport == .basketball })
            #expect(roster.count == PlayerFactory.rosterPositions(team.tier, sport: .basketball).count)
            #expect(game.canField(team))
            #expect(Balance.strengthRange(team.tier).contains(game.strength(of: team.id).rounded()))
        }
        #expect(game.career?.goal != nil)
        #expect(Set(game.careerTrainableKeys) == Set(Attributes.weights(for: position).map(\.0)))
        #expect(SaveSlot.career(for: .basketball) == .basketballPlayer)
        #expect(SaveSlot.basketballPlayer.sport == .basketball && SaveSlot.basketballPlayer.isCareer)
    }

    @Test func 한_경기를_치르면_기록과_평점이_남는다() throws {
        var game = TestCareer.make(.shootingGuard, seed: 4)
        let before = try #require(game.myPlayer).ability
        try game.startMatch(now: TestGame.hours(1))
        let live = try #require(game.liveBasketball)
        #expect(live.others.count == 4)
        #expect(game.isMatchLive)
        // 경기 도중에 저장했다가 불러와도 그대로 이어진다.
        for _ in 0..<100 { game.stepMatch() }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("basket-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try SaveStore(fileURL: url).save(GameSave(game: game))
        var loaded = try #require(try SaveStore(fileURL: url).load()).game
        #expect(loaded == game)
        #expect(game.menuBarText(now: TestGame.hours(1), todayTokens: 0).hasPrefix("🏀"))
        #expect(game.careerLivePerformance != nil)
        game.runMatchToEnd()
        loaded.runMatchToEnd()
        #expect(loaded == game)

        #expect(!game.isMatchLive && game.round == 1)
        let me = try #require(game.myPlayer)
        #expect(me.basketball?.games == 1)
        #expect((me.basketball?.seconds ?? 0) > 0)
        let rating = try #require(game.career?.lastRating)
        #expect((1...10).contains(rating))
        #expect(game.career?.lastLine?.contains("분") == true)
        #expect(me.ability > before)
        #expect(game.lastResult?.myRuns != game.lastResult?.theirRuns)
        // 여섯 리그 모두 한 라운드를 치렀다.
        for tier in LeagueTier.allCases {
            #expect(game.standings[tier.index].allSatisfy { $0.games == 1 && $0.draws == 0 })
        }
    }

    @Test func 벤치에서_시작해도_정해진_시간은_뛰고_잘하면_선발이_된다() throws {
        var game = TestCareer.make(.center5, seed: 6)
        let id = try #require(game.career?.playerID)
        for key in Attributes.Key.all(for: .basketball) { game.players[id]?.attributes[key] = 5 }
        game.career?.trust = 40
        #expect(game.careerBasketballPlan?.starts == false)
        #expect(game.careerBasketballPlan?.minutes == Balance.careerBenchMinutes(trust: 40))
        try game.startMatch(now: TestGame.hours(1))
        let live = try #require(game.liveBasketball)
        let side = live.userIsHome ? live.state.home : live.state.away
        let mine = try #require(side.players.first { $0.playerID == id })
        #expect(!mine.isStarter && side.featured == id)
        game.runMatchToEnd()
        let minutes = (game.myPlayer?.basketball?.seconds ?? 0) / 60
        #expect(abs(minutes - Balance.careerBenchMinutes(trust: 40)) <= 5)

        for key in Attributes.Key.all(for: .basketball) { game.players[id]?.attributes[key] = 60 }
        #expect(game.careerBasketballPlan?.starts == true)
        try game.startMatch(now: TestGame.hours(2))
        let next = try #require(game.liveBasketball)
        let nextSide = next.userIsHome ? next.state.home : next.state.away
        #expect(nextSide.players.first { $0.playerID == id }?.isStarter == true)
        #expect(nextSide.players.filter(\.isStarter).count == 5)
        game.runMatchToEnd()
    }

    @Test(arguments: [(Position.pointGuard, UInt64(21)), (.powerForward, UInt64(22))])
    func 두_시즌을_돌려도_멈추지_않고_세계가_농구로_남는다(position: Position, seed: UInt64) throws {
        var game = TestCareer.make(position, seed: seed)
        var auto = CareerAuto()
        var guardCount = 0
        while game.season < 3, guardCount < 140 {
            guardCount += 1
            guard game.nextMatch() != nil else { break }
            try auto.playOne(&game)
        }
        #expect(game.season == 3)
        #expect(game.teams.count == 60)
        for tier in LeagueTier.allCases {
            #expect(game.teams(in: tier).count == 10)
            for team in game.teams(in: tier) {
                let roster = game.roster(of: team.id)
                #expect(roster.allSatisfy { $0.position.sport == .basketball }, "\(team.name)")
                #expect(roster.count >= Balance.basketballStarters, "\(team.name) \(roster.count)명")
                #expect(roster.count <= game.rosterLimit(tier), "\(team.name) \(roster.count)명")
                // 포지션이 한쪽으로 쏠리지 않는다: 다섯 포지션에 적어도 한 명씩 있다.
                #expect(Set(roster.map(\.position)).count == 5, "\(team.name) \(roster.map(\.position.rawValue))")
            }
        }
        let career = try #require(game.career)
        #expect(Set(career.history.map(\.season)).count == 2)
        #expect(career.history.allSatisfy { ($0.basketball?.games ?? 0) > 0 })
        #expect(game.awards.contains { $0.title == "득점왕" })
        #expect(game.cup?.season == 3)
        // 새 시즌을 몇 경기 치르면 기록 순위가 다시 채워진다.
        for _ in 0..<3 { try auto.playOne(&game) }
        #expect(game.leaders(.pro).count == 6 && game.leaders(.pro).allSatisfy { !$0.rows.isEmpty })
        #expect(game.careerBasketballTotals.games > 30)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("basket2-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try SaveStore(fileURL: url).save(GameSave(game: game))
        #expect(try SaveStore(fileURL: url).load()?.game == game)
    }

    @Test func 벤치에서_한_시즌을_보내도_감독_신뢰가_무너지지_않는다() throws {
        for (position, seed) in [(Position.shootingGuard, UInt64(42)), (.smallForward, 41), (.center5, 42)] {
            var game = TestCareer.make(position, seed: seed)
            var clock = TestGame.start
            while game.season == 1, game.phase == .regular, game.nextMatch() != nil {
                clock = clock.addingTimeInterval(3600)
                try game.startMatch(now: clock)
                game.runMatchToEnd()
            }
            let career = try #require(game.career)
            // 훈련을 한 번도 하지 않은 벤치 선수: 재계약 기준(30) 아래로 떨어지지 않는다.
            #expect(career.trust >= Balance.careerRenewalTrust, "\(position.label) 신뢰 \(career.trust)")
            // 라이벌은 같은 포지션이다.
            if let rival = game.careerRival { #expect(rival.position == position) }
        }
    }

    @Test func 평점은_포지션과_출전_시간에_따라_고르게_나온다() throws {
        var report = ""
        for position in Position.basketball {
            for starter in [true, false] {
                var game = TestCareer.make(position, seed: 31)
                let id = try #require(game.career?.playerID)
                // 리그 평균 수준의 선수로 맞춘다. 선발이면 조금 높게.
                let level = starter ? 44.0 : 24.0
                for (key, _) in Attributes.weights(for: position) { game.players[id]?.attributes[key] = level }
                game.players[id]?.potential = level
                var total = 0.0, count = 0, minutes = 0, points = 0
                var clock = TestGame.start
                for _ in 0..<36 {
                    guard let next = game.nextMatch() else { break }
                    clock = clock.addingTimeInterval(3600)
                    game.career?.trust = 40
                    try game.startMatch(now: clock)
                    game.runMatchToEnd()
                    if next.kind == .regular, let rating = game.career?.lastRating {
                        total += rating
                        count += 1
                    }
                }
                if let line = game.myPlayer?.basketball { minutes = line.seconds / 60 / max(1, line.games); points = line.points / max(1, line.games) }
                let average = total / Double(max(1, count))
                report += " [\(position.rawValue) \(starter ? "선발" : "벤치") \(String(format: "%.2f", average)) \(minutes)분 \(points)점]"
                #expect((starter ? 6.2...7.2 : 5.8...6.5).contains(average), "\(position.label) \(starter) \(average)")
            }
        }
        print("BASKETRATING\(report)")
    }
}
