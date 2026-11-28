import Foundation
import Testing
@testable import TokenBaseballCore

/// e스포츠 개인 대회, 칭호, 활동, 시상 (→ docs/10-esports.md "개인 리그", "칭호").
@Suite struct DuelCircuitTests {
    @Test func 팬이_모자라면_나가지_못하고_백_명이면_PC방_대회에_나간다() throws {
        var game = TestCareer.make(.human, seed: 31)
        #expect(!game.canEnterDuel(.pcBang))
        game.career?.fans = 150
        #expect(game.canEnterDuel(.pcBang))
        #expect(!game.canEnterDuel(.city))
        game.playDuelTournament(.pcBang)
        let event = try #require(game.career?.duelEvents?.last)
        #expect(event.tournament == .pcBang)
        #expect(event.name.hasSuffix("PC방 배"))
        #expect(["우승", "준우승", "4강", "8강", "16강"].contains(event.finish))
        #expect((game.career?.fans ?? 0) >= 150)
        #expect(game.news.contains { $0.text.contains(event.name) })
    }

    @Test func 큰_선수는_동네_대회에_나가지_않는다() {
        var game = TestCareer.make(.alien, seed: 32)
        game.career?.fans = 20_000
        #expect(game.entersDuel(.national))
        #expect(game.entersDuel(.city))
        #expect(!game.entersDuel(.pcBang))
    }

    @Test func 우승하면_칭호가_붙고_바로_위_대회에_초대받는다() throws {
        var game = TestCareer.make(.protector, seed: 33)
        // 능력을 크게 올려 PC방 대회를 우승하게 한다.
        let id = try #require(game.career?.playerID)
        for key in Attributes.Key.all(for: .duel) { game.players[id]?.attributes[key] = 95 }
        game.career?.fans = 120
        var guardCount = 0
        while (game.career?.duelWins?[DuelTournament.pcBang.rawValue - 1] ?? 0) == 0, guardCount < 5 {
            game.playDuelTournament(.pcBang)
            guardCount += 1
        }
        #expect(game.career?.duelWins?[DuelTournament.pcBang.rawValue - 1] ?? 0 >= 1)
        #expect(game.duelTitle == "동네 고수")
        #expect(game.career?.duelInvite == DuelTournament.city.rawValue)
        #expect(game.canEnterDuel(.city))
        #expect(game.career?.awards.contains { $0.contains("PC방 배 우승") } == true)
    }

    @Test func 칭호는_우승_횟수와_팬_수로_바뀐다() {
        var game = TestCareer.make(.human, seed: 34)
        game.career?.fans = 50
        #expect(game.duelTitle == nil)
        game.career?.fans = 200_000
        #expect(game.duelTitle == "무관의 스타")
        var wins = Array(repeating: 0, count: 6)
        wins[DuelTournament.korea.rawValue - 1] = 3
        game.career?.duelWins = wins
        #expect(game.duelTitle == "왕")
        game.career?.fans = 2_000_000
        #expect(game.duelTitle == "국민 왕")
        game.career?.fans = 5_000
        #expect(game.duelTitle == "숨은 왕")
        wins[DuelTournament.world.rawValue - 1] = 1
        game.career?.duelWins = wins
        game.career?.fans = 12_000_000
        #expect(game.duelTitle == "모두의 세계 챔피언")
    }

    @Test func 시즌을_치르면_대회가_열리고_시상과_기록_순위가_나온다() throws {
        var game = TestCareer.make(.alien, seed: 35)
        game.career?.fans = 100
        var auto = CareerAuto()
        while game.season == 1 { try auto.playOne(&game) }
        let events = game.career?.duelEvents ?? []
        #expect(events.contains { $0.season == 1 && $0.tournament == .pcBang })
        #expect(game.cup == nil)
        let season1 = game.awards.filter { $0.season == 1 }
        #expect(season1.contains { $0.title == "MVP" })
        #expect(season1.contains { $0.title == "다승왕" })
        let boards = game.leaders(.citizenAmateur)
        #expect(boards.map(\.title) == ["세트 승", "세트 승률", "에이스 결정전"])
        #expect(!(boards.first?.rows.isEmpty ?? true))
    }

    @Test func 활동은_팬을_늘린다() throws {
        var game = TestCareer.make(.human, seed: 36)
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        #expect(CareerActivity.interview.label(for: .duel) == "개인 방송")
        let before = game.career?.fans ?? 0
        let expected = try #require(game.careerActivityFans(.youthClinic))
        let macro = try #require(game.myPlayer).attributes.macro
        try game.doCareerActivity(.youthClinic)
        #expect(game.career?.fans == before + expected)
        #expect((game.myPlayer?.attributes.macro ?? 0) > macro)
        #expect(throws: GameError.self) { try game.doCareerActivity(.interview) }
    }
}
