import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerCriticalTests {
    func make() -> Game {
        var game = Game.newCareer(
            setup: CareerSetup(name: "훈련 선수", position: .shortstop), now: Date(timeIntervalSince1970: 0), seed: 91)
        game.funds.earn(100_000_000, .tokens)
        return game
    }

    @Test func 크리티컬이_터지면_같은_포인트로_세_배_오른다() throws {
        var normal = make()
        var lucky = normal
        let key = normal.careerTrainableKeys[0]
        let before = normal.myPlayer!.attributes[key]
        let gain = normal.careerTrainingGain(key)
        try normal.trainCareer(key, critical: false)
        try lucky.trainCareer(key, critical: true)
        #expect(abs(normal.myPlayer!.attributes[key] - before - gain) < 0.0001)
        #expect(abs(lucky.myPlayer!.attributes[key] - before - gain * Balance.careerCriticalMultiplier) < 0.0001)
        #expect(lucky.funds.balance == normal.funds.balance)
        #expect(lucky.career?.lastCritical != nil && lucky.career?.criticalCount == 1)
        #expect(normal.career?.lastCritical == nil)
        // 다음 훈련이 보통이면 표시가 지워진다.
        try lucky.trainCareer(key, critical: false)
        #expect(lucky.career?.lastCritical == nil && lucky.career?.criticalCount == 1)
    }

    @Test func 크리티컬도_한계를_넘지_못한다() throws {
        var game = make()
        let key = game.careerTrainableKeys[0]
        var me = game.myPlayer!
        me.potential = me.ability + game.careerTrainingStep * 1.5
        game.players[me.id] = me
        try game.trainCareer(key, critical: true)
        #expect(game.myPlayer!.ability <= game.myPlayer!.potential + 0.0001)
    }

    @Test func 크리티컬은_백_번에_한_번쯤_터진다() throws {
        var game = make()
        game.funds.earn(2_000_000_000_000, .tokens)
        var count = 0
        let total = 20_000
        for _ in 0..<total where game.rng.chance(Balance.careerCriticalChance) { count += 1 }
        #expect(count > total / 200 && count < total / 50)
    }
}
