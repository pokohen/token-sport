import Foundation

/// 선수 생성.
public enum PlayerFactory {
    /// 목표 능력에 맞는 세부 능력치를 만든다. 가중 평균이 목표 능력과 같아지게 맞춘다.
    static func attributes(position: Position, ability: Double, _ rng: inout SeededRNG) -> Attributes {
        var attributes = Attributes()
        let weights = Attributes.weights(for: position)
        let relevant = Set(weights.map { $0.0 })

        for key in Attributes.Key.all(for: position.sport) {
            if relevant.contains(key) {
                attributes[key] = clamp(ability + rng.gaussian() * 6, 1, 99)
            } else if position.sport == .football {
                // 제 포지션에 덜 중요한 능력치. 골키핑은 골키퍼가 아니면 거의 없다.
                let share = key == .keeping ? 0.15 : position == .goalkeeper ? 0.3 : 0.6
                attributes[key] = clamp(ability * share + rng.gaussian() * 4, 1, 70)
            } else if position.sport == .basketball {
                // 제 포지션에 덜 중요한 능력치.
                attributes[key] = clamp(ability * 0.6 + rng.gaussian() * 4, 1, 75)
            } else if position.isPitcher {
                // 투수의 타격·수비 능력치 (지명타자 제도라 타석에는 서지 않는다)
                attributes[key] = clamp(ability * 0.4 + rng.gaussian() * 3, 1, 60)
            } else {
                attributes[key] = clamp(ability * 0.25 + rng.gaussian() * 3, 1, 40)
            }
        }
        // 가중 평균을 목표에 맞춘다.
        for _ in 0..<4 {
            let current = weights.reduce(0) { $0 + attributes[$1.0] * $1.1 }
            let shift = ability - current
            if abs(shift) < 0.01 { break }
            for (key, _) in weights {
                attributes[key] = clamp(attributes[key] + shift, 1, 99)
            }
        }
        return attributes
    }

    public struct Spec {
        public var position: Position
        public var tier: LeagueTier
        public var season: Int
        public var ability: ClosedRange<Double>?
        public var age: ClosedRange<Int>?
        /// 잠재력을 직접 정할 때.
        public var potential: ClosedRange<Double>?
        public var foreign = false
        public var scoutBias: Double?

        public init(position: Position, tier: LeagueTier, season: Int) {
            self.position = position
            self.tier = tier
            self.season = season
        }
    }

    public static func make(id: PlayerID, spec: Spec, _ rng: inout SeededRNG) -> Player {
        let tier = spec.tier
        let ability = rng.double(spec.ability ?? Balance.abilityRange(tier))
        let age = rng.int(spec.age ?? Balance.ageRange(tier))

        var potential: Double
        if let range = spec.potential {
            potential = max(ability, rng.double(range))
        } else {
            // 나이가 많을수록 더 클 여지가 적다.
            let room = age <= 24 ? 1.0 : age <= 28 ? 0.6 : age <= 31 ? 0.25 : 0.0
            potential = ability + rng.double(0...Balance.potentialBonus(tier)) * room
            if tier == .citizenAmateur { potential = min(potential, 45) }
        }
        potential = clamp(potential, ability, 99)

        var traits: [Trait] = []
        let pool = Trait.pool(for: spec.position)
        if rng.chance(0.25), !pool.isEmpty { traits.append(rng.pick(pool)) }
        if rng.chance(0.06), pool.count > 1 {
            let extra = rng.pick(pool)
            if !traits.contains(extra) { traits.append(extra) }
        }

        let years = tier.isCitizen ? rng.int(1...2) : rng.int(1...3)
        let clause = !tier.isCitizen && rng.chance(0.2)
        let salary = Balance.marketSalary(ability: ability) * (spec.foreign ? 2 : 1)

        let sport = spec.position.sport
        var player = Player(
            id: id,
            name: spec.foreign ? NameGenerator.foreignName(&rng) : NameGenerator.playerName(&rng, sport: sport),
            age: age,
            position: spec.position,
            bats: rng.chance(0.3) ? .left : .right,
            throwsHand: rng.chance(0.25) ? .left : .right,
            attributes: attributes(position: spec.position, ability: ability, &rng),
            potential: potential,
            scoutBias: spec.scoutBias ?? rng.gaussian(),
            contract: Contract(salary: salary, seasonsLeft: years, relegationClause: clause),
            teamID: nil,
            origin: spec.foreign ? "해외 리그 출신" : NameGenerator.origin(tier: tier, sport: sport, &rng),
            traits: traits,
            isForeign: spec.foreign,
            joinedSeason: spec.season,
            joinedTier: tier.rawValue,
            isFranchiseStar: false,
            batting: BattingLine(),
            pitching: PitchingLine(),
            football: sport == .football ? FootballLine() : nil,
            basketball: sport == .basketball ? BasketballLine() : nil,
            lastStartGame: -99,
            abilityAtSeasonStart: ability,
            isHot: false
        )
        // 세부 능력치를 맞추다 생긴 작은 오차 때문에 능력이 잠재력을 넘지 않게 한다.
        player.potential = max(player.potential, player.ability)
        player.abilityAtSeasonStart = player.ability
        return player
    }

    /// 한 팀 로스터의 포지션 목록.
    public static func rosterPositions(_ tier: LeagueTier, sport: Sport = .baseball) -> [Position] {
        if sport == .football {
            let shape = Balance.footballShape(tier)
            return Array(repeating: Position.goalkeeper, count: shape.keepers)
                + Array(repeating: .defender, count: shape.defenders)
                + Array(repeating: .midfielder, count: shape.midfielders)
                + Array(repeating: .forward, count: shape.forwards)
        }
        if sport == .basketball {
            return zip(Position.basketball, Balance.basketballShape(tier)).flatMap { position, count in
                Array(repeating: position, count: count)
            }
        }
        let shape = Balance.rosterShape(tier)
        var positions: [Position] = Position.fieldPositions + [.designated]
        let extras: [Position] = [.catcher, .shortstop, .center, .first, .third, .left, .second, .right]
        var index = 0
        while positions.count < shape.batters {
            positions.append(extras[index % extras.count])
            index += 1
        }
        positions += Array(repeating: .starter, count: shape.starters)
        positions += Array(repeating: .reliever, count: shape.relievers - 1)
        positions.append(.closer)
        return positions
    }
}
