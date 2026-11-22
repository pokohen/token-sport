import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerMidSeasonTransferTests {
    /// 시즌 도중에 옮기면 지금까지의 기록은 옛 구단의 줄로 남고, 새 리그에서는 0부터 센다.
    private func check(_ position: Position, played: (Player) -> Int) throws {
        var game = TestCareer.make(position, seed: 7)
        var auto = CareerAuto()
        for _ in 0..<6 { try auto.playOne(&game) }
        #expect(game.phase == .regular)
        let before = try #require(game.myPlayer)
        let rated = try #require(game.career?.seasonRatedGames)
        try #require(rated > 0)
        let oldName = game.teams[game.userTeamID].name
        let oldTier = game.userTier
        let fullGoal = try #require(game.career?.goal?.target)
        let totalsBefore = game.careerTotals.ratedGames

        let target = try #require(game.teams(in: .citizenSemiPro).first).id
        game.career?.offers = [CareerOffer(
            id: 901, kind: .transfer, teamID: target, salary: 5_000_000, years: 2, role: .rotation, matchesLeft: 1)]
        try game.acceptCareerOffer(901)

        let me = try #require(game.myPlayer)
        let career = try #require(game.career)
        // 새 리그의 시즌 기록은 비어 있다.
        #expect(played(me) == 0)
        #expect(career.seasonRatedGames == 0)
        // 옛 구단의 기록은 커리어에 한 줄로 남는다.
        let row = try #require(career.history.last)
        #expect(row.season == game.season)
        #expect(row.teamName == oldName)
        #expect(row.tier == oldTier)
        #expect(row.ratedGames == rated)
        #expect(played(before) > 0)
        // 통산 기록은 그대로다.
        #expect(game.careerTotals.ratedGames == totalsBefore)
        // 아직 끝나지 않은 시즌은 치른 시즌으로 세지 않는다.
        #expect(game.careerSeasonsPlayed == 0)
        // 시즌 목표는 새 구단(윗 리그) 기준으로, 남은 경기만큼이라 처음보다 작다.
        #expect((career.goal?.target ?? .max) < fullGoal)
        #expect(career.goal?.achieved != true)

        // 남은 시즌을 마치면 같은 시즌의 두 번째 줄이 새 구단으로 남는다.
        while game.career?.seasonClosed == false { try auto.playOne(&game) }
        let rows = try #require(game.career?.history.filter { $0.season == row.season })
        #expect(rows.count == 2)
        #expect(rows.last?.teamName == game.teams[target].name)
        #expect(game.careerSeasonsPlayed == 1)
    }

    @Test func 야구() throws {
        try check(.shortstop) { $0.batting.plateAppearances }
    }

    @Test func 축구() throws {
        try check(.forward) { $0.football?.games ?? 0 }
    }

    @Test func 농구() throws {
        try check(.shootingGuard) { $0.basketball?.games ?? 0 }
    }

    @Test func 목표는_남은_경기만큼_줄어든다() {
        var game = TestCareer.make(.forward, seed: 7)
        game.assignCareerGoal(announce: false)
        let full = game.career!.goal!.target
        game.assignCareerGoal(announce: false, remaining: 0.5)
        #expect(game.career!.goal!.target == max(1, Int((Double(full) * 0.5).rounded())))
    }
}
