import Foundation

/// 선수 모드: 훈련 포인트(토큰)로 능력치를 올린다.
extension Game {
    // MARK: 훈련

    /// 훈련으로 올릴 수 있는 능력치 (내 포지션의 능력에 들어가는 것만).
    public var careerTrainableKeys: [Attributes.Key] {
        guard let me = myPlayer else { return [] }
        return Attributes.weights(for: me.position).map(\.0)
    }

    /// 훈련 한 번에 그 능력치가 오르는 양.
    /// 어떤 훈련이든 능력(CA)이 똑같이 오르도록, 포지션에서 덜 중요한 능력치일수록 많이 오른다.
    /// (그러지 않으면 능력치가 적은 투수·골키퍼가 야수·필드 선수보다 훨씬 빨리 큰다.)
    public func careerTrainingGain(_ key: Attributes.Key) -> Double {
        guard let me = myPlayer,
              let weight = Attributes.weights(for: me.position).first(where: { $0.0 == key })?.1, weight > 0
        else { return 0 }
        // 한계까지 남은 만큼만 오른다 (마지막 훈련은 덜 오를 수 있다).
        let step = min(careerTrainingStep, max(0, me.potential - me.ability))
        return min(step / weight, 99 - me.attributes[key])
    }

    /// 지금 리그에서 훈련 한 번에 오르는 능력(CA). 윗 리그일수록 크다. 무소속이면 마지막 구단의 리그를 따른다.
    public var careerTrainingStep: Double { Balance.careerTrainingStep(userTier) }

    /// 지금 리그의 훈련 비용 배수. 윗 리그일수록 비싸다.
    public var careerTrainingCostFactor: Double { Balance.careerTrainingCostFactor(userTier) }

    /// 설정: 정해진 횟수를 넘겨서도 훈련할 수 있는지.
    public var careerExtraTrainingEnabled: Bool { settings.extraTraining ?? false }

    public mutating func setCareerExtraTraining(_ on: Bool) { settings.extraTraining = on ? true : nil }

    /// 이번 경기 사이에 정해진 횟수를 넘겨 한 추가 훈련의 수.
    public var careerExtraSessionsUsed: Int { max(0, -(career?.sessionsLeft ?? 0)) }

    /// 지금 하는 훈련이 추가 훈련이면 비용에 곱하는 값 (첫 추가 훈련 1.5배, 그다음 2.25배…). 아니면 1.
    public var careerSessionCostMultiplier: Double {
        guard let career, career.sessionsLeft <= 0, careerExtraTrainingEnabled else { return 1 }
        return pow(Balance.careerExtraSessionCost, Double(1 - career.sessionsLeft))
    }

    /// 훈련 횟수를 다 썼고 추가 훈련도 할 수 없는지.
    var careerSessionsExhausted: Bool {
        guard let career else { return true }
        return career.sessionsLeft <= 0 && !careerExtraTrainingEnabled
    }

    /// 훈련 한 번에 드는 훈련 포인트. 지금 값이 높을수록, 한계에 가까울수록, 추가 훈련일수록 비싸다.
    public func careerTrainingCost(_ key: Attributes.Key) -> Int {
        guard let me = myPlayer else { return 0 }
        var cost = Balance.careerTrainingCost(value: me.attributes[key])
        if me.potential - me.ability <= Balance.careerNearPotentialRoom { cost *= 2 }
        return price(Int((Double(cost) * careerSessionCostMultiplier * careerTrainingCostFactor).rounded()))
    }

    /// 지금 이 훈련을 할 수 없는 이유. 할 수 있으면 nil.
    public func careerTrainingBlockedReason(_ key: Attributes.Key) -> String? {
        guard let career, !career.retired, let me = players[career.playerID] else { return "선수가 없습니다." }
        guard Attributes.weights(for: me.position).contains(where: { $0.0 == key }) else {
            return "이 포지션에서는 올릴 수 없는 능력치입니다."
        }
        if me.age >= Balance.careerTrainingAgeLimit(me.position) {
            return "\(Balance.careerTrainingAgeLimit(me.position))세부터는 훈련으로 능력치를 올릴 수 없습니다."
        }
        if careerSessionsExhausted { return "다음 경기를 치르면 다시 훈련할 수 있습니다." }
        if me.attributes[key] >= 99 { return "이미 최고치입니다." }
        if me.potential - me.ability < 0.01 {
            return "한계에 닿았습니다. 지금은 더 오르지 않습니다."
        }
        let cost = careerTrainingCost(key)
        if let reason = insufficientFundsReason(cost) { return reason }
        return nil
    }

    /// 훈련 포인트(토큰)를 써서 능력치 하나를 올린다. 경기와 경기 사이에 정해진 횟수만큼 할 수 있고,
    /// 설정에서 추가 훈련을 켜면 그 뒤로도 점점 비싼 값에 할 수 있다.
    /// 100번에 한 번꼴로 크리티컬이 터져 같은 포인트로 세 배 오른다.
    public mutating func trainCareer(_ key: Attributes.Key) throws {
        try trainCareer(key, critical: nil)
    }

    /// `critical`을 주면 크리티컬 여부를 정해 놓고 훈련한다 (테스트용). nil이면 확률대로.
    mutating func trainCareer(_ key: Attributes.Key, critical forced: Bool?) throws {
        if let reason = careerTrainingBlockedReason(key) { throw GameError(reason) }
        guard var career, var me = players[career.playerID] else { return }
        funds.spend(careerTrainingCost(key), .training)
        let critical = forced ?? rng.chance(Balance.careerCriticalChance)
        var gain = careerTrainingGain(key)
        if critical {
            // 세 배까지. 다만 한계(잠재력)와 최고치 99는 넘지 않는다.
            let room = max(1, (me.potential - me.ability) / careerTrainingStep)
            gain = min(gain * min(Balance.careerCriticalMultiplier, room), 99 - me.attributes[key])
        }
        me.attributes[key] = min(99, me.attributes[key] + gain)
        players[me.id] = me
        career.sessionsLeft -= 1
        career.trainingCount += 1
        if critical {
            career.criticalCount = (career.criticalCount ?? 0) + 1
            career.lastCritical = "크리티컬! \(CareerDrill.name(key, sport: sport))이(가) 아주 잘됐습니다: +\(String(format: "%.2f", gain))"
        } else {
            career.lastCritical = nil
        }
        // 꾸준히 훈련하면 감독도 조금씩 알아준다.
        career.trust = min(100, career.trust + 0.1)
        career.peakAbility = max(career.peakAbility, me.ability)
        self.career = career
    }

    /// 한계 돌파 훈련에 드는 훈련 포인트. 추가 훈련이면 더 든다.
    public var careerBreakthroughCost: Int {
        price(Int((Double(Balance.careerBreakthroughCost) * careerSessionCostMultiplier).rounded()))
    }

    public var careerBreakthroughBlockedReason: String? {
        guard let career, !career.retired, let me = players[career.playerID] else { return "선수가 없습니다." }
        if me.age >= Balance.careerTrainingAgeLimit(me.position) {
            return "\(Balance.careerTrainingAgeLimit(me.position))세부터는 한계를 넓힐 수 없습니다."
        }
        if careerSessionsExhausted { return "다음 경기를 치르면 다시 훈련할 수 있습니다." }
        if me.potential >= 99 { return "더 넓힐 한계가 없습니다." }
        return insufficientFundsReason(careerBreakthroughCost)
    }

    /// 한계 돌파 훈련: 큰 포인트를 들여 잠재력(능력의 한계)을 +1 넓힌다. 훈련 횟수를 한 번 쓴다.
    public mutating func breakThroughCareer() throws {
        if let reason = careerBreakthroughBlockedReason { throw GameError(reason) }
        guard var career, var me = players[career.playerID] else { return }
        funds.spend(careerBreakthroughCost, .training)
        me.potential = min(99, me.potential + 1)
        players[me.id] = me
        career.sessionsLeft -= 1
        career.trainingCount += 1
        self.career = career
    }
}
