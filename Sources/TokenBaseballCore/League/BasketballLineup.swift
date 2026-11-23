import Foundation

/// 농구 한 경기에 나서는 선수 구성.
public struct BasketballLineup: Equatable, Sendable {
    /// 선발 다섯 명과 서는 자리. 포인트 가드 → 센터 순.
    public var starters: [(id: PlayerID, slot: Position)]
    /// 벤치. 능력 순.
    public var bench: [PlayerID]

    public static func == (lhs: BasketballLineup, rhs: BasketballLineup) -> Bool {
        lhs.bench == rhs.bench && lhs.starters.map(\.id) == rhs.starters.map(\.id)
            && lhs.starters.map(\.slot) == rhs.starters.map(\.slot)
    }
}

public enum BasketballLineupBuilder {
    /// 제 포지션이 아닌 자리에 서면 능력이 이만큼만 나온다.
    static let outOfPosition = 0.9

    /// 포지션마다 능력이 가장 좋은 선수를 선발로 세운다. 정해 둔 선발 다섯 명이 있고 쓸 수 있으면 그것을 따른다.
    /// 농구 선수가 다섯 명은 있어야 한다.
    public static func build(team: Team, players: [PlayerID: Player]) -> BasketballLineup? {
        let roster = team.roster.compactMap { players[$0] }.filter { $0.position.sport == .basketball }
        guard roster.count >= Balance.basketballStarters else { return nil }
        let ranked = roster.sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }

        var chosen: [Player]
        let override = team.lineupOverride.compactMap { players[$0] }
            .filter { player in roster.contains { $0.id == player.id } }
        if override.count == Balance.basketballStarters, Set(override.map(\.id)).count == override.count {
            chosen = override
        } else {
            chosen = []
            var remaining = ranked
            for slot in Position.basketball {
                if let index = remaining.firstIndex(where: { $0.position == slot }) {
                    chosen.append(remaining.remove(at: index))
                }
            }
            // 비는 포지션은 남은 선수 중 능력이 좋은 순으로 메운다.
            while chosen.count < Balance.basketballStarters, !remaining.isEmpty {
                chosen.append(remaining.removeFirst())
            }
        }
        guard chosen.count == Balance.basketballStarters else { return nil }

        // 자리 나누기: 제 포지션부터 채우고, 남은 선수가 빈자리를 메운다.
        var open = Position.basketball
        var assigned: [PlayerID: Position] = [:]
        for player in chosen {
            if let index = open.firstIndex(of: player.position) {
                assigned[player.id] = player.position
                open.remove(at: index)
            }
        }
        for player in chosen where assigned[player.id] == nil {
            assigned[player.id] = open.isEmpty ? player.position : open.removeFirst()
        }
        let order = Position.basketball
        let starters = chosen
            .sorted {
                let a = order.firstIndex(of: assigned[$0.id] ?? .center5) ?? 0
                let b = order.firstIndex(of: assigned[$1.id] ?? .center5) ?? 0
                return (a, $0.id) < (b, $1.id)
            }
            .map { (id: $0.id, slot: assigned[$0.id] ?? $0.position) }
        let ids = Set(chosen.map(\.id))
        return BasketballLineup(starters: starters, bench: ranked.filter { !ids.contains($0.id) }.map(\.id))
    }

    /// 경기 엔진에 넘길 팀 구성.
    public static func side(team: Team, players: [PlayerID: Player]) -> BasketballSide? {
        guard let lineup = build(team: team, players: players) else { return nil }
        func state(_ id: PlayerID, slot: Position, starts: Bool) -> BasketballPlayerState? {
            guard let player = players[id] else { return nil }
            let a = player.attributes
            let factor = slot == player.position ? 1.0 : outOfPosition
            let hot = player.isHot ? 3.0 : 0.0
            return BasketballPlayerState(
                playerID: player.id, name: player.name, natural: player.position, slot: slot,
                shooting: a.shooting * factor + hot, three: a.three * factor + hot,
                passing: a.passing * factor, dribbling: a.dribbling * factor,
                defense: a.tackling * factor, rebounding: a.rebounding * factor,
                speed: a.speed * factor, physical: a.physical * factor, stamina: a.stamina,
                traits: player.traits, starts: starts)
        }
        let starters = lineup.starters.compactMap { state($0.id, slot: $0.slot, starts: true) }
        let bench = lineup.bench.compactMap { id in
            players[id].flatMap { state(id, slot: $0.position, starts: false) }
        }
        guard starters.count == Balance.basketballStarters else { return nil }
        return BasketballSide(
            teamID: team.id, name: team.name, shortName: team.shortName, players: starters + bench)
    }

    /// 팀 강도를 정하는 선수들: 자동으로 짠 선발 다섯 명과 벤치에서 가장 좋은 세 명.
    public static func core(team: Team, players: [PlayerID: Player]) -> [Player] {
        var auto = team
        auto.lineupOverride = []
        if let lineup = build(team: auto, players: players) {
            return (lineup.starters.map(\.id) + lineup.bench.prefix(3)).compactMap { players[$0] }
        }
        return team.roster.compactMap { players[$0] }
            .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
            .prefix(Balance.basketballStarters).map { $0 }
    }

    /// 팀 강도 = 선발 다섯 명(비중 80%)과 벤치 세 명(20%)의 능력.
    public static func strength(team: Team, players: [PlayerID: Player]) -> Double {
        let group = core(team: team, players: players)
        guard !group.isEmpty else { return 0 }
        let five = group.prefix(Balance.basketballStarters)
        let rest = group.dropFirst(Balance.basketballStarters)
        let first = five.reduce(0) { $0 + $1.ability } / Double(five.count)
        guard !rest.isEmpty else { return first }
        return first * 0.8 + rest.reduce(0) { $0 + $1.ability } / Double(rest.count) * 0.2
    }
}
