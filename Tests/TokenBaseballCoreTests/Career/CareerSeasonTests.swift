import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerSeasonTests {
    @Test(arguments: [(Position.shortstop, UInt64(21)), (.starter, 22), (.reliever, 23), (.catcher, 24)])
    func 세_시즌을_보내도_멈추지_않고_선수가_자란다(position: Position, seed: UInt64) throws {
        var game = TestCareer.make(position, seed: seed)
        var auto = CareerAuto()
        let start = try #require(game.myPlayer).ability
        var guardCount = 0
        while game.season <= 3 {
            try auto.playOne(&game)
            guardCount += 1
            #expect(guardCount < 400)
            let career = try #require(game.career)
            if !career.isFreeAgent {
                let me = try #require(game.myPlayer)
                #expect(me.teamID == game.userTeamID)
                #expect(game.teams[game.userTeamID].roster.contains(me.id))
            }
            #expect(game.teams.allSatisfy { !$0.isUser })
            #expect((0.0...100.0).contains(career.trust))
            #expect((0.0...100.0).contains(career.fame))
        }
        let career = try #require(game.career)
        let me = try #require(game.myPlayer)
        #expect(Set(career.history.map(\.season)).count == 3)
        #expect(me.age == 19)
        #expect(me.ability > start + 10)
        #expect(me.ability <= me.potential + 0.001)
        #expect(career.earnings > 0)
        #expect(career.trainingCount > 60)
        #expect(career.history.allSatisfy { $0.ratedGames > 0 })
        let totals = game.careerTotals
        #expect(totals.ratedGames == career.history.reduce(0) { $0 + $1.ratedGames } + career.seasonRatedGames)
    }

    @Test func 은퇴하면_명예의_전당에_남고_같은_세계에서_새_선수로_시작한다() throws {
        var game = TestCareer.make(.third, seed: 31)
        var auto = CareerAuto()
        let id = try #require(game.career?.playerID)
        // 첫 시즌 도중에는 은퇴할 수 없다.
        #expect(!game.canRetireCareer)
        #expect(throws: GameError.self) { try game.retireCareer() }
        while game.phase != .offseason { try auto.playOne(&game) }
        // 한 시즌을 마친 오프시즌에는 나이와 상관없이 은퇴할 수 있다.
        #expect(game.myPlayer?.age ?? 99 < 20)
        #expect(game.canRetireCareer && game.careerRetireBlockedReason == nil)
        let club = game.userTeamID
        try game.retireCareer()
        #expect(game.career?.retired == true)
        #expect(game.myPlayer == nil)
        #expect(game.players[id] == nil)
        #expect(!game.teams[club].roster.contains(id))
        #expect(game.nextMatch() == nil)
        let record = try #require(game.careerHall?.last)
        #expect(record.name == "김테스트")
        #expect(record.batting.games == Balance.roundsPerSeason)
        #expect(record.clubs.count >= 1)
        #expect(record.seasons == 1 && record.honor == "동네 스타")

        let teams = game.teams.map(\.name)
        try game.startNewCareer(
            setup: CareerSetup(name: "이새싹", position: .reliever), now: auto.clock.addingTimeInterval(60))
        let rookie = try #require(game.myPlayer)
        #expect(rookie.name == "이새싹")
        #expect(rookie.age == Balance.careerStartAge)
        #expect(game.career?.retired == false)
        #expect(game.career?.history.isEmpty == true)
        #expect(game.teams.map(\.name) == teams)
        #expect(game.funds.balance == FundsLedger.startingFunds)
        #expect(game.careerHall?.count == 1)
        // 오프시즌에 만든 선수의 첫 시즌은 다음 시즌이고, 예전 선수가 사 둔 경기는 넘어오지 않는다.
        #expect(game.career?.firstSeason == 2)
        #expect(game.extraMatchPending == nil)
        for _ in 0..<8 { try auto.playOne(&game) }
        #expect(game.season == 2)
    }

    @Test func 서른여덟_살_시즌이_끝나면_은퇴한다() throws {
        var game = TestCareer.make(.first, seed: 32)
        var auto = CareerAuto()
        let id = try #require(game.career?.playerID)
        game.players[id]?.age = Balance.careerForcedRetirementAge - 1
        while game.career?.retired != true {
            try auto.playOne(&game)
            #expect(game.season == 1)
        }
        #expect(game.careerHall?.last?.retiredAge == Balance.careerForcedRetirementAge)
    }

    @Test func 구단이_승격하면_내_선수도_윗_리그에서_뛴다() throws {
        var game = TestCareer.make(.center, seed: 33)
        let salary = try #require(game.myPlayer).contract.salary
        game.careerClubMoved(from: .citizenAmateur, to: .citizenSemiPro)
        #expect(try #require(game.myPlayer).contract.salary > salary)
        #expect(game.career?.bestTier == .citizenSemiPro)
    }
}
