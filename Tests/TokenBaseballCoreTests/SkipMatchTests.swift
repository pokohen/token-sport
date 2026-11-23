import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct SkipMatchTests {
    /// 경기 도중에 결과 바로 보기를 쓴 쪽과 끝까지 지켜본 쪽이 같은 결과를 내는지 본다.
    private func expectSameResult(_ start: Game, steps: Int) throws {
        var game = start
        TestGame.addTokens(&game, 10_000_000, id: "skip", at: TestGame.hours(1))
        try game.startMatch(now: TestGame.hours(1))
        for _ in 0..<steps { game.stepMatch() }

        var watched = game
        watched.runMatchToEnd()

        let cost = game.skipMatchCost
        #expect(game.skipMatchBlockedReason == nil)
        try game.skipMatchToEnd()

        // 경기가 끝나며 들고 나는 돈(관중 수입, 연봉)은 지켜본 쪽과 같고, 값만큼만 적다.
        #expect(game.funds.balance == watched.funds.balance - cost)
        #expect(game.funds.seasonExpense[FundsLedger.Category.skipMatch.rawValue] == cost)
        // 값만 빼면 지켜본 쪽과 세계가 똑같다 (경기 결과, 순위, 기록 모두).
        watched.funds = game.funds
        #expect(game == watched)
        // 경기가 끝나면 더 쓸 수 없다.
        #expect(game.skipMatchBlockedReason != nil)
        #expect(throws: GameError.self) { try game.skipMatchToEnd() }
    }

    @Test func 야구_결과가_지켜본_것과_같다() throws {
        try expectSameResult(TestGame.make(), steps: 40)
    }

    @Test func 축구_결과가_지켜본_것과_같다() throws {
        try expectSameResult(FootballGame.make(), steps: 30)
    }

    @Test func 농구_선수_모드_결과가_지켜본_것과_같다() throws {
        try expectSameResult(TestCareer.make(.pointGuard), steps: 0)
    }

    @Test func 토큰이_모자라면_할_수_없다() throws {
        var game = TestGame.make()
        try game.startMatch(now: TestGame.hours(1))
        game.funds.spend(game.funds.balance, .training)
        #expect(game.skipMatchBlockedReason != nil)
        #expect(throws: GameError.self) { try game.skipMatchToEnd() }
        #expect(game.isMatchLive)
    }
}
