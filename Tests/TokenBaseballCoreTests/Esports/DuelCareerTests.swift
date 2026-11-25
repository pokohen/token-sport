import Foundation
import Testing
@testable import TokenBaseballCore

/// e스포츠 1:1 대전 선수 모드: 팀 경기, 세트 배정, 평점, 팬 (→ docs/10-esports.md 만드는 순서 4).
@Suite struct DuelCareerTests {
    @Test func 팀_경기는_세트를_치르고_순위표에_세트_득실이_남는다() throws {
        var game = TestCareer.make(.human, seed: 21)
        TestGame.addTokens(&game, 1_000_000, id: "a", at: TestGame.hours(1))
        try game.startMatch(now: TestGame.hours(1))
        let live = try #require(game.liveDuel)
        #expect(live.state.bestOf == 3)
        #expect(game.menuBarText(now: TestGame.hours(1), todayTokens: 0).hasPrefix("🎮 0:0"))
        game.runMatchToEnd()
        let result = try #require(game.lastResult)
        #expect(max(result.myRuns, result.theirRuns) == 2)
        #expect(game.round == 1)
        let rows = game.standings[game.userTier.index]
        #expect(rows.reduce(0) { $0 + $1.wins } == 5)
        #expect(rows.reduce(0) { $0 + $1.runsFor } == rows.reduce(0) { $0 + $1.runsAgainst })
        #expect(rows.allSatisfy { $0.runsFor + $0.runsAgainst >= 2 })
    }

    @Test func 에이스는_1세트와_결정전에_나간다() {
        let game = TestCareer.make(.alien, seed: 22)
        let teams = game.teams(in: .pro)
        let lineup = game.duelLineup(teams[0].id, bestOf: 3)!
        #expect(lineup.count == 2)
        var match = game.makeDuelMatch(home: teams[0].id, away: teams[1].id, kind: .regular, seed: 3)!
        match.runToEnd()
        #expect(match.records[0].home.playerID == lineup[0])
        if match.records.count > 1 { #expect(match.records[1].home.playerID == lineup[1]) }
        if match.records.count == 3 {
            #expect(match.records[2].decider)
            #expect(match.records[2].home.playerID == lineup[0])
        }
        #expect(game.duelLineup(teams[0].id, bestOf: 5)!.count == 4)
    }

    @Test func 순서에_들지_못해도_네_경기에_한_번은_나온다() throws {
        var game = TestCareer.make(.protector, seed: 23)
        var auto = CareerAuto()
        auto.tokensPerMatch = 0
        var appeared = 0
        for _ in 0..<12 {
            try auto.playOne(&game)
            if game.career?.lastRating != nil { appeared += 1 }
        }
        // 갓 들어온 16세라 팀에서 가장 약하다. 그래도 12경기 중 세 번은 나온다.
        #expect(appeared >= 3)
    }

    @Test func 세트_평점은_이기면_오르고_큰_경기에서_더_움직인다() {
        func stats(_ overall: Double, killed: Double = 40, lost: Double = 40) -> DuelMatch.SetStats {
            .init(playerID: 1, name: "가", race: .human, overall: overall, armyKilled: killed, armyLost: lost,
                  workersKilled: 0, workersLost: 0, worstDeficit: 0)
        }
        let win = Game.duelSetRating(won: true, me: stats(60), them: stats(60), ticks: 70, stakes: .regular, decider: false)
        let loss = Game.duelSetRating(won: false, me: stats(60), them: stats(60), ticks: 70, stakes: .regular, decider: false)
        let aceWin = Game.duelSetRating(won: true, me: stats(60), them: stats(60), ticks: 70, stakes: .ace, decider: true)
        let upset = Game.duelSetRating(won: true, me: stats(50), them: stats(65), ticks: 70, stakes: .regular, decider: false)
        let rout = Game.duelSetRating(won: true, me: stats(60, killed: 90, lost: 10), them: stats(60), ticks: 40, stakes: .regular, decider: false)
        #expect(win > 6.5 && loss < 5.6)
        #expect(aceWin > win)
        #expect(upset > win)
        #expect(rout > win)
    }

    @Test func 팬은_세트를_이기면_늘고_명성은_팬에서_나온다() throws {
        var game = TestCareer.make(.human, seed: 24)
        #expect(game.career?.fans == 0)
        var auto = CareerAuto()
        for _ in 0..<20 { try auto.playOne(&game) }
        let career = try #require(game.career)
        let fans = try #require(career.fans)
        #expect(fans > 0)
        #expect(abs(career.fame - Balance.duelFame(fans: fans)) < 1e-9)
        #expect(Balance.duelFame(fans: 100) > 28 && Balance.duelFame(fans: 100) < 30)
        #expect(Balance.duelFame(fans: 10_000_000) == 100)
        #expect(fansText(32_000) == "3.2만 명")
        #expect(fansText(1_240) == "1,240명")
        #expect(fansText(10_000_000) == "1,000만 명")
    }

    @Test func 경기_도중에_저장했다가_이어도_같다() throws {
        var game = TestCareer.make(.alien, seed: 25)
        try game.startMatch(now: TestGame.hours(1))
        for _ in 0..<40 { game.stepMatch() }
        let data = try JSONEncoder().encode(game)
        var restored = try JSONDecoder().decode(Game.self, from: data)
        #expect(restored == game)
        game.runMatchToEnd()
        restored.runMatchToEnd()
        #expect(restored == game)
    }

    @Test(arguments: [(Position.human, UInt64(81)), (.alien, 82), (.protector, 83)])
    func 세_시즌을_보내도_멈추지_않는다(position: Position, seed: UInt64) throws {
        var game = TestCareer.make(position, seed: seed)
        var auto = CareerAuto()
        let start = try #require(game.myPlayer).ability
        var count = 0
        while game.season <= 3 {
            try auto.playOne(&game)
            count += 1
            #expect(count < 400)
        }
        let career = try #require(game.career)
        let me = try #require(game.myPlayer)
        #expect(Set(career.history.map(\.season)).count == 3)
        #expect(career.history.allSatisfy { $0.duel != nil && $0.ratedGames > 0 })
        #expect(me.age == 19)
        // 어릴 때 크게 큰다.
        #expect(me.ability > start + 10)
        #expect(me.ability <= me.potential + 0.001)
        #expect(game.careerDuelTotals.sets > 20)
        #expect((career.fans ?? 0) > 100)
    }
}

extension DuelCareerTests {
    @Test func 서른다섯_시즌을_마치면_은퇴하고_명예의_전당에_팬과_칭호가_남는다() throws {
        var game = TestCareer.make(.human, seed: 26)
        let id = try #require(game.career?.playerID)
        game.players[id]?.age = 35
        game.career?.fans = 250_000
        var auto = CareerAuto()
        var count = 0
        while game.career?.retired == false, count < 200 {
            try auto.playOne(&game)
            count += 1
        }
        let record = try #require(game.careerHall?.last)
        #expect(record.retiredAge == 36)
        #expect(record.duel != nil)
        #expect((record.fans ?? 0) > 0)
        #expect(record.honor == "무관의 스타")
    }

    @Test func 팀을_옮겨도_네_경기에_한_번은_나온다() throws {
        var game = TestCareer.make(.alien, seed: 27)
        var auto = CareerAuto()
        for _ in 0..<6 { try auto.playOne(&game) }
        let id = try #require(game.career?.playerID)
        // 다른 팀으로 옮긴다: 옛 팀의 경기 번호가 남아 있어도 보장은 새 팀 기준으로 센다.
        let target = try #require(game.teams(in: .citizenAmateur).first { $0.id != game.userTeamID })
        game.career?.offers = [CareerOffer(id: 999, kind: .transfer, teamID: target.id, salary: 1_000_000, years: 1, role: .prospect, matchesLeft: 5)]
        try game.acceptCareerOffer(999)
        #expect(game.userTeamID == target.id)
        var appeared = 0
        for _ in 0..<8 {
            try auto.playOne(&game)
            if game.career?.lastRating != nil { appeared += 1 }
        }
        #expect(game.players[id]?.teamID == target.id)
        #expect(appeared >= 2)
    }
}
