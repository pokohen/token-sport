import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerTrainingTests {
    @Test func 훈련_포인트를_써서_능력치를_올린다() throws {
        var game = TestCareer.make(.shortstop)
        #expect(Set(game.careerTrainableKeys) == [.contact, .power, .eye, .speed, .fielding, .arm])
        // 시작 포인트(10만)로는 첫 훈련을 할 수 없다.
        #expect(throws: GameError.self) { try game.trainCareer(.contact) }

        TestGame.addTokens(&game, 10_000_000, id: "a", at: TestGame.hours(1))
        let before = try #require(game.myPlayer)
        let cost = game.careerTrainingCost(.contact)
        #expect(cost == Int((Double(Balance.careerTrainingCost(value: before.attributes.contact)) * Balance.careerTrainingCostFactor(.citizenAmateur)).rounded()))
        let balance = game.funds.balance
        try game.trainCareer(.contact)
        let after = try #require(game.myPlayer)
        // 어떤 훈련이든 능력이 같은 양만큼 오른다.
        #expect(abs(after.ability - before.ability - Balance.careerTrainingStep(.citizenAmateur)) < 0.0001)
        #expect(after.attributes.contact > before.attributes.contact + 0.05)
        #expect(after.ability > before.ability)
        #expect(game.funds.balance == balance - cost)
        #expect(game.funds.seasonExpense[FundsLedger.Category.training.rawValue] == cost)
    }

    @Test func 경기_사이에_정해진_횟수만_훈련한다() throws {
        var game = TestCareer.make(.starter)
        #expect(Set(game.careerTrainableKeys) == [.stuff, .control, .breaking, .stamina])
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        for _ in 0..<Balance.careerSessionsPerMatch { try game.trainCareer(.stuff) }
        #expect(game.career?.sessionsLeft == 0)
        #expect(throws: GameError.self) { try game.trainCareer(.control) }
        // 타자 능력치는 투수가 올릴 수 없다.
        #expect(game.careerTrainingBlockedReason(.contact) != nil)

        try TestGame.playOne(&game, at: TestGame.hours(2))
        #expect(game.career?.sessionsLeft == Balance.careerSessionsPerMatch)
        try game.trainCareer(.control)
    }

    @Test func 추가_훈련을_켜면_횟수를_넘겨서도_점점_비싼_값에_훈련한다() throws {
        var game = TestCareer.make(.starter)
        TestGame.addTokens(&game, 500_000_000, id: "a", at: TestGame.hours(1))
        // 기본은 꺼져 있다: 다섯 번까지만.
        #expect(!game.careerExtraTrainingEnabled)
        for _ in 0..<Balance.careerSessionsPerMatch { try game.trainCareer(.stamina) }
        #expect(game.careerTrainingBlockedReason(.control) != nil)
        #expect(game.careerBreakthroughBlockedReason != nil)
        #expect(game.careerSessionCostMultiplier == 1)
        let base = game.careerTrainingCost(.control)
        let breakthrough = game.careerBreakthroughCost

        game.setCareerExtraTraining(true)
        #expect(game.careerTrainingBlockedReason(.control) == nil)
        // 첫 추가 훈련은 1.5배, 그다음은 2.25배.
        #expect(game.careerSessionCostMultiplier == 1.5)
        #expect(game.careerTrainingCost(.control) == Int((Double(base) * 1.5).rounded()))
        #expect(game.careerBreakthroughCost == Int((Double(breakthrough) * 1.5).rounded()))
        var balance = game.funds.balance
        try game.trainCareer(.control)
        #expect(game.funds.balance == balance - Int((Double(base) * 1.5).rounded()))
        #expect(game.careerExtraSessionsUsed == 1)
        #expect(game.careerSessionCostMultiplier == 2.25)
        // 한계 돌파도 횟수를 쓰므로 같이 비싸진다.
        balance = game.funds.balance
        try game.breakThroughCareer()
        #expect(game.funds.balance == balance - Int((Double(breakthrough) * 2.25).rounded()))
        #expect(game.careerExtraSessionsUsed == 2)

        // 끄면 다시 막힌다.
        game.setCareerExtraTraining(false)
        #expect(game.careerTrainingBlockedReason(.control) != nil)
        game.setCareerExtraTraining(true)

        // 저장했다가 불러와도 그대로다.
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("extra-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try SaveStore(fileURL: url).save(GameSave(game: game))
        #expect(try SaveStore(fileURL: url).load()?.game == game)

        // 다음 경기를 치르면 처음 값으로 돌아간다.
        try TestGame.playOne(&game, at: TestGame.hours(2))
        #expect(game.careerSessionCostMultiplier == 1)
        #expect(game.careerExtraSessionsUsed == 0)
    }

    @Test func 가격_난이도가_훈련_비용에도_적용된다() {
        var game = TestCareer.make(.first)
        let normal = game.careerTrainingCost(.power)
        game.settings.priceDifficulty = 0.5
        #expect(game.careerTrainingCost(.power) == normal / 2)
    }

    @Test func 잠재력과_나이가_훈련의_한계다() throws {
        var game = TestCareer.make(.first)
        TestGame.addTokens(&game, 500_000_000, id: "a", at: TestGame.hours(1))
        let id = try #require(game.career?.playerID)

        // 한계에 가까우면 비용이 두 배.
        let cost = game.careerTrainingCost(.power)
        let ability = try #require(game.myPlayer).ability
        game.players[id]?.potential = ability + 5
        #expect(game.careerTrainingCost(.power) == cost * 2)
        // 한계에 닿으면 오르지 않는다.
        game.players[id]?.potential = ability
        #expect(throws: GameError.self) { try game.trainCareer(.power) }

        game.players[id]?.potential = 90
        game.players[id]?.age = Balance.careerTrainingAgeLimit
        #expect(throws: GameError.self) { try game.trainCareer(.power) }
        game.players[id]?.age = Balance.careerTrainingAgeLimit - 1
        try game.trainCareer(.power)
    }
}

@Suite struct CareerCostTests {
    @Test func 훈련할_때마다_비용이_조금씩_오른다() throws {
        var game = TestCareer.make(.starter)
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        let first = game.careerTrainingCost(.stuff)
        for _ in 0..<Balance.careerSessionsPerMatch { try game.trainCareer(.stuff) }
        let second = game.careerTrainingCost(.stuff)
        #expect(second > first)
        #expect(Double(second) < Double(first) * 1.15)
        // 값이 오를수록 계속 비싸진다.
        let costs = stride(from: 1.0, through: 99.0, by: 1).map { Balance.careerTrainingCost(value: $0) }
        #expect(zip(costs, costs.dropFirst()).allSatisfy { $0 <= $1 })
        #expect(Balance.careerTrainingCost(value: 25) == 250_000)
    }
}
