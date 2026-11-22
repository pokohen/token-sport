import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerFootballStartTests {
    @Test(arguments: Position.football)
    func 축구_선수로_6부_구단에_입단한다(position: Position) throws {
        let game = TestCareer.make(position, seed: 61)
        let me = try #require(game.myPlayer)
        #expect(game.sport == .football)
        #expect(game.teams.count == 120)
        #expect(game.teams.allSatisfy { !$0.isUser })
        #expect(me.position == position)
        #expect(me.age == Balance.careerStartAge)
        #expect(me.football != nil)
        #expect(game.userTier == .citizenAmateur)
        // 같은 포지션 선수의 자리를 넘겨받으므로 포지션별 인원은 그대로다.
        let roster = game.roster(of: game.userTeamID)
        let shape = PlayerFactory.rosterPositions(.citizenAmateur, sport: .football)
        #expect(roster.count == shape.count)
        for slot in Position.football {
            #expect(roster.filter { $0.position == slot }.count == shape.filter { $0 == slot }.count)
        }
        #expect(game.career?.goal != nil)
        #expect(Set(game.careerTrainableKeys) == Set(Attributes.weights(for: position).map(\.0)))
    }

    @Test func 축구_훈련_이름은_야구와_다르다() {
        #expect(CareerDrill.name(.shooting, sport: .football) == "슈팅 연습")
        #expect(CareerDrill.name(.speed, sport: .football) == "스프린트")
        #expect(CareerDrill.name(.speed, sport: .baseball) == "주루 훈련")
    }

    @Test func 야구_세계에서는_축구_선수를_만들_수_없다() throws {
        var game = TestCareer.make(.first, seed: 62)
        var auto = CareerAuto()
        while game.phase != .offseason { try auto.playOne(&game) }
        try game.retireCareer()
        #expect(throws: GameError.self) {
            try game.startNewCareer(setup: CareerSetup(name: "축구", position: .forward), now: auto.clock)
        }
    }
}

@Suite struct CareerFootballAppearanceTests {
    @Test func 주전이_아니면_벤치에서_시작해_정해진_시간에_반드시_들어간다() throws {
        var game = TestCareer.make(.forward, seed: 63)
        let id = try #require(game.career?.playerID)
        // 능력을 바닥으로 내려 선발에서 밀리게 한다.
        for key in Attributes.Key.all(for: .football) { game.players[id]?.attributes[key] = 5 }
        game.career?.trust = 40
        #expect(game.careerFootballPlan?.starts == false)
        #expect(game.careerFootballPlan?.subMinute == Balance.careerSubMinute(trust: 40))

        try game.startMatch(now: TestGame.hours(1))
        let live = try #require(game.liveFootball)
        let side = live.userIsHome ? live.state.home : live.state.away
        let index = try #require(side.players.firstIndex { $0.playerID == id })
        #expect(index >= Balance.footballStarters)
        #expect(!side.players[index].isOnPitch)
        #expect(side.guaranteedSub == id)

        game.runMatchToEnd()
        let me = try #require(game.myPlayer)
        #expect(me.football?.games == 1)
        #expect(game.career?.lastRating != nil)
        let line = try #require(game.career?.lastLine)
        let minutes = try #require(Int(line.prefix { $0.isNumber }))
        #expect(minutes > 0 && minutes <= 90 - Balance.careerSubMinute(trust: 40) + 15)
    }

    @Test func 감독_신뢰가_높으면_일찍_들어가고_능력이_좋으면_선발이다() throws {
        #expect(Balance.careerSubMinute(trust: 20) == 80)
        #expect(Balance.careerSubMinute(trust: 60) == 60)
        #expect(Balance.careerSubMinute(trust: 100) == 50)

        var game = TestCareer.make(.midfielder, seed: 64)
        let id = try #require(game.career?.playerID)
        for key in Attributes.Key.all(for: .football) { game.players[id]?.attributes[key] = 60 }
        game.players[id]?.potential = 90
        #expect(game.careerFootballPlan?.starts == true)
        try game.startMatch(now: TestGame.hours(1))
        let live = try #require(game.liveFootball)
        let side = live.userIsHome ? live.state.home : live.state.away
        let index = try #require(side.players.firstIndex { $0.playerID == id })
        #expect(index < Balance.footballStarters)
        #expect(side.players[index].detail != nil)
        #expect(side.guaranteedSub == nil)
        game.runMatchToEnd()
        let line = try #require(game.career?.lastLine)
        #expect(line.hasPrefix("9") || line.hasPrefix("8") || line.hasPrefix("7") || line.hasPrefix("6"))
    }

    @Test func 주전이_아닌_골키퍼는_네_경기에_한_번_선발로_나온다() throws {
        var game = TestCareer.make(.goalkeeper, seed: 65)
        let id = try #require(game.career?.playerID)
        game.players[id]?.attributes.keeping = 3
        var auto = CareerAuto()
        auto.tokensPerMatch = 0
        var played = 0
        for _ in 0..<12 {
            let starts = game.careerFootballPlan?.starts == true
            try auto.playOne(&game)
            let appeared = game.career?.lastRating != nil
            #expect(appeared == starts)
            if appeared { played += 1 }
        }
        #expect(played == 12 / Balance.careerKeeperRotation)
    }

    @Test func 욕심내기는_슈팅이_늘고_연계는_줄어든다() throws {
        func shots(_ style: PlayStyle) throws -> Int {
            var game = TestCareer.make(.forward, seed: 66)
            let id = try #require(game.career?.playerID)
            for key in Attributes.Key.all(for: .football) { game.players[id]?.attributes[key] = 45 }
            game.players[id]?.potential = 90
            game.setCareerStyle(style)
            var auto = CareerAuto()
            auto.tokensPerMatch = 0
            for _ in 0..<30 { try auto.playOne(&game) }
            return game.myPlayer?.football?.shots ?? 0
        }
        let greedy = try shots(.greedy), balanced = try shots(.balanced), link = try shots(.link)
        #expect(greedy > balanced)
        #expect(balanced > link)
    }

    @Test func 평점은_골과_무실점에_오르고_짧게_뛰면_6점에_가깝다() {
        func side(_ natural: Position, ticks: Int, _ edit: (inout FootballPlayerState) -> Void) -> FootballSide {
            var player = FootballPlayerState(
                playerID: 1, name: "선수", natural: natural, slot: natural, shooting: 50, passing: 50, dribbling: 50,
                tackling: 50, speed: 50, physical: 50, keeping: 50, stamina: 50, traits: [], starts: true)
            player.detail = FootballDetail()
            player.detail?.ticks = ticks
            edit(&player)
            return FootballSide(teamID: 0, name: "팀", shortName: "팀", players: [player], tactic: .balanced)
        }
        let full = 270
        let scorer = Game.careerFootballPerformance(
            playerID: 1, in: side(.forward, ticks: full) { $0.line.goals = 2; $0.line.shotsOnTarget = 3 },
            conceded: 1, result: 1)
        let quiet = Game.careerFootballPerformance(
            playerID: 1, in: side(.forward, ticks: full) { _ in }, conceded: 2, result: -1)
        let cameo = Game.careerFootballPerformance(
            playerID: 1, in: side(.forward, ticks: 30) { $0.line.goals = 2; $0.line.shotsOnTarget = 3 },
            conceded: 1, result: 1)
        let wall = Game.careerFootballPerformance(
            playerID: 1, in: side(.defender, ticks: full) { $0.detail?.tackles = 4 }, conceded: 0, result: 0)
        let sentOff = Game.careerFootballPerformance(
            playerID: 1, in: side(.midfielder, ticks: 120) { $0.line.redCards = 1; $0.detail?.fouls = 2 },
            conceded: 1, result: -1)
        #expect(scorer!.rating > 8.5)
        #expect(quiet!.rating < 6.2)
        #expect(cameo!.rating < scorer!.rating)
        #expect(wall!.rating > 6.8)
        #expect(sentOff!.rating < 5)
        #expect(scorer?.line == "90분 2골 슈팅 0")
        var bench = side(.forward, ticks: 0) { _ in }
        bench.players[0].hasPlayed = false
        #expect(Game.careerFootballPerformance(playerID: 1, in: bench, conceded: 0, result: 0) == nil)
    }
}

@Suite struct CareerFootballSeasonTests {
    @Test(arguments: [(Position.forward, UInt64(71)), (.midfielder, 72), (.defender, 73), (.goalkeeper, 74)])
    func 세_시즌을_보내도_멈추지_않는다(position: Position, seed: UInt64) throws {
        var game = TestCareer.make(position, seed: seed)
        var auto = CareerAuto()
        let start = try #require(game.myPlayer).ability
        var count = 0
        while game.season <= 3 {
            try auto.playOne(&game)
            count += 1
            #expect(count < 400)
            let career = try #require(game.career)
            if !career.isFreeAgent {
                let me = try #require(game.myPlayer)
                #expect(me.teamID == game.userTeamID)
                #expect(game.teams[game.userTeamID].roster.contains(me.id))
            }
            #expect(game.teams.allSatisfy { !$0.isUser })
        }
        let career = try #require(game.career)
        let me = try #require(game.myPlayer)
        #expect(Set(career.history.map(\.season)).count == 3)
        #expect(career.history.allSatisfy { $0.football != nil && $0.ratedGames > 0 })
        #expect(me.ability > start + 10)
        #expect(me.ability <= me.potential + 0.001)
        #expect(game.careerFootballTotals.games
            == career.history.reduce(0) { $0 + ($1.football?.games ?? 0) } + (me.football?.games ?? 0))
    }

    @Test func 축구_선수도_구단을_옮기고_은퇴한다() throws {
        var game = TestCareer.make(.defender, seed: 75)
        var auto = CareerAuto()
        let target = try #require(game.teams(in: .citizenSemiPro).first).id
        let size = game.teams[target].roster.count
        game.career?.offers = [CareerOffer(
            id: 970, kind: .transfer, teamID: target, salary: 2_000_000, years: 2, role: .rotation, matchesLeft: 1)]
        try game.acceptCareerOffer(970)
        #expect(game.userTeamID == target)
        #expect(game.teams[target].roster.count == size)
        while game.phase != .offseason { try auto.playOne(&game) }
        try game.retireCareer()
        let record = try #require(game.careerHall?.last)
        #expect(record.position == .defender)
        #expect((record.football?.games ?? 0) > 0)
        try game.startNewCareer(setup: CareerSetup(name: "새싹", position: .goalkeeper), now: auto.clock)
        #expect(game.myPlayer?.position == .goalkeeper)
    }

    @Test func 축구_선수_모드는_저장_파일을_따로_쓴다() {
        let store = SaveStore(fileURL: URL(fileURLWithPath: "/tmp/x/save.json"))
        #expect(SaveSlot.footballPlayer.sport == .football)
        #expect(SaveSlot.footballPlayer.isCareer)
        #expect(store.sibling(slot: .footballPlayer).fileURL.lastPathComponent == "save-football-player.json")
        #expect(SaveSlot.career(for: .football) == .footballPlayer)
        #expect(SaveSlot.career(for: .baseball) == .baseballPlayer)
    }
}
