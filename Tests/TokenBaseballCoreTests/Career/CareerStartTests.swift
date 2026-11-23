import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerStartTests {
    @Test func 구단_모드에는_선수_모드_상태가_없다() {
        let game = TestGame.make()
        #expect(game.career == nil)
        #expect(!game.isCareer)
        #expect(game.myPlayer == nil)
    }

    @Test(arguments: [Position.shortstop, .catcher, .designated, .starter, .reliever])
    func 열여섯_살에_6부_구단에_입단한다(position: Position) throws {
        let game = TestCareer.make(position)
        let me = try #require(game.myPlayer)
        #expect(game.teams.count == 60)
        #expect(game.teams.allSatisfy { !$0.isUser })
        #expect(me.name == "김테스트")
        #expect(me.age == 16)
        #expect(me.position == position)
        #expect(me.bats == .left)
        #expect(me.teamID == game.userTeamID)
        #expect(game.userTier == .citizenAmateur)
        #expect(Balance.careerPotential.contains(me.potential))
        #expect(Balance.careerStartAbility.contains(me.ability.rounded()))
        #expect(game.career?.startAbility == me.ability)
        #expect(game.careerTalent == CareerTalent(potential: me.potential))
        #expect(game.news.contains { $0.text.contains("스카우트 평가") && $0.text.contains("타고난 능력 \(Int(me.ability))") })
        #expect(game.funds.balance == FundsLedger.startingFunds)
        // 같은 포지션 선수의 자리를 넘겨받으므로 로스터 구성은 그대로다.
        let roster = game.roster(of: game.userTeamID)
        #expect(roster.count == PlayerFactory.rosterPositions(.citizenAmateur, sport: .baseball).count)
        #expect(roster.map(\.position).sorted { $0.rawValue < $1.rawValue }
            == PlayerFactory.rosterPositions(.citizenAmateur, sport: .baseball).sorted { $0.rawValue < $1.rawValue })
        #expect(game.career?.clubs == [game.userTeam.name])
        #expect(game.career?.goal != nil)
    }

    @Test func 재능은_선수마다_다르게_타고난다() throws {
        var abilities: Set<Int> = []
        var potentials: Set<Int> = []
        for seed in 1...12 {
            let me = try #require(TestCareer.make(.shortstop, seed: UInt64(seed)).myPlayer)
            #expect(me.ability <= me.potential)
            #expect(Balance.careerPotential.contains(me.potential))
            abilities.insert(Int(me.ability))
            potentials.insert(Int(me.potential))
        }
        #expect(abilities.count >= 5)
        #expect(potentials.count >= 5)
    }

    @Test(arguments: [Position.shortstop, .starter, .forward, .goalkeeper])
    func 시작_포인트를_넣은_능력치가_오른다(position: Position) throws {
        let keys = Attributes.weights(for: position).map(\.0)
        func make(_ points: [Attributes.Key: Int]) -> Game {
            Game.newCareer(
                setup: CareerSetup(name: "포인트", position: position, points: points), now: TestGame.start, seed: 3)
        }
        let plain = try #require(make([:]).myPlayer)
        let game = make([keys[0]: 2, keys[1]: 2, keys[2]: 1])
        let me = try #require(game.myPlayer)
        #expect(abs(me.attributes[keys[0]] - (plain.attributes[keys[0]] + 2 * Balance.careerStartPointValue)) < 0.001)
        #expect(abs(me.attributes[keys[1]] - (plain.attributes[keys[1]] + 2 * Balance.careerStartPointValue)) < 0.001)
        #expect(abs(me.attributes[keys[2]] - (plain.attributes[keys[2]] + Balance.careerStartPointValue)) < 0.001)
        for key in keys.dropFirst(3) { #expect(me.attributes[key] == plain.attributes[key]) }
        #expect(me.ability > plain.ability)
        #expect(me.ability <= me.potential)
        #expect(me.abilityAtSeasonStart == me.ability)
        #expect(game.career?.peakAbility == me.ability)
        // 타고난 재능은 포인트를 넣기 전의 값이다.
        #expect(game.career?.startAbility == plain.ability)
        #expect(me.potential == plain.potential)
    }

    @Test func 시작_포인트는_다섯_개까지만_내_포지션에만_들어간다() throws {
        let over = CareerSetup(name: "욕심", position: .forward, points: [.shooting: 4, .dribbling: 4, .speed: 3, .keeping: 5, .physical: -2])
        #expect(over.validPoints.map(\.0) == [.shooting, .dribbling, .speed])
        #expect(over.validPoints.map(\.1) == [2, 2, 1])
        #expect(over.pointsUsed == Balance.careerStartPoints)
        #expect(over.pointsLeft == 0)
        let plain = try #require(Game.newCareer(
            setup: CareerSetup(name: "욕심", position: .forward), now: TestGame.start, seed: 3).myPlayer)
        let me = try #require(Game.newCareer(setup: over, now: TestGame.start, seed: 3).myPlayer)
        #expect(abs(me.attributes[.shooting] - (plain.attributes[.shooting] + 2 * Balance.careerStartPointValue)) < 0.001)
        #expect(abs(me.attributes[.dribbling] - (plain.attributes[.dribbling] + 2 * Balance.careerStartPointValue)) < 0.001)
        #expect(me.attributes[.keeping] == plain.attributes[.keeping])
        #expect(abs(me.attributes[.speed] - (plain.attributes[.speed] + Balance.careerStartPointValue)) < 0.001)
        #expect(me.attributes[.physical] == plain.attributes[.physical])
    }

    @Test(arguments: [Position.shortstop, .reliever, .forward])
    func 경기를_치르면_능력이_오르고_결과에_적힌다(position: Position) throws {
        var game = TestCareer.make(position, seed: 5)
        let before = try #require(game.myPlayer).ability
        try game.startMatch(now: TestGame.hours(1))
        game.runMatchToEnd()
        let gained = try #require(game.myPlayer).ability - before
        #expect(gained > 0.05)
        #expect(game.lastResult?.summary.contains("이번 경기 성장: 능력 +\(String(format: "%.2f", gained))") == true)
        #expect(game.career?.peakAbility == game.myPlayer?.ability)
    }

    @Test func 저장했다가_불러와도_그대로다() throws {
        var game = TestCareer.make(.starter, seed: 7)
        var auto = CareerAuto()
        for _ in 0..<3 { try auto.playOne(&game) }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("career-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = SaveStore(fileURL: url)
        try store.save(GameSave(game: game))
        #expect(try store.load()?.game == game)
    }
}

@Suite struct CareerExtraTests {
    @Test func 한계_돌파_훈련은_잠재력을_넓힌다() throws {
        var game = TestCareer.make(.starter)
        #expect(throws: GameError.self) { try game.breakThroughCareer() }
        TestGame.addTokens(&game, 100_000_000, id: "a", at: TestGame.hours(1))
        let before = try #require(game.myPlayer).potential
        let balance = game.funds.balance
        try game.breakThroughCareer()
        #expect(try #require(game.myPlayer).potential == min(99, before + 1))
        #expect(game.funds.balance == balance - Balance.careerBreakthroughCost)
        #expect(game.career?.sessionsLeft == Balance.careerSessionsPerMatch - 1)
    }

    @Test func 선수_모드는_저장_파일을_따로_쓴다() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("slot-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let store = SaveStore(fileURL: folder.appendingPathComponent("save.json"))
        #expect(store.sibling(slot: SaveSlot.baseball).fileURL.lastPathComponent == "save.json")
        #expect(store.sibling(slot: SaveSlot.football).fileURL.lastPathComponent == "save-football.json")
        #expect(store.sibling(slot: SaveSlot.baseballPlayer).fileURL.lastPathComponent == "save-baseball-player.json")
        #expect(store.sibling(for: Sport.football).fileURL == store.sibling(slot: SaveSlot.football).fileURL)

        #expect(store.loadActiveSlot() == .baseball)
        try store.saveActiveSlot(.baseballPlayer)
        #expect(store.loadActiveSlot() == .baseballPlayer)
        #expect(store.loadActiveSport() == .baseball)
        // 예전에 종목 이름으로 적어 둔 파일도 그대로 읽힌다.
        try store.saveActiveSport(.football)
        #expect(store.loadActiveSlot() == .football)
    }

    @Test func 상단바에는_훈련_포인트가_나온다() {
        let game = TestCareer.make(.center)
        #expect(game.menuBarText(now: TestGame.start, todayTokens: 0) == "100.0K P •")
        #expect(game.menuBarTooltip(now: TestGame.start, todayTokens: 0).contains("훈련 포인트"))
    }

    @Test func 수상하면_명성이_오르고_커리어에_남는다() throws {
        var game = TestCareer.make(.center, seed: 41)
        let id = try #require(game.career?.playerID)
        var auto = CareerAuto()
        // 리그를 압도하는 타자로 만든다.
        for key in [Attributes.Key.contact, .power, .eye] { game.players[id]?.attributes[key] = 95 }
        game.players[id]?.potential = 99
        while game.phase == .regular { try auto.playOne(&game) }
        let career = try #require(game.career)
        #expect(!career.awards.isEmpty)
        // 시즌 도중에 옮겼으면 시상은 시즌을 마친 구단의 줄에 붙는다.
        #expect(career.history.last?.awards.isEmpty == false)
        #expect(game.awards.contains { $0.isMine && $0.playerName == "김테스트" })
        #expect(game.awards.filter(\.isMine).allSatisfy { $0.playerName == "김테스트" })
    }
}
