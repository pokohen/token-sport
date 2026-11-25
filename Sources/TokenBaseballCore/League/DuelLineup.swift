import Foundation

/// e스포츠 1:1 대전 팀의 출전 순서. 팀 경기는 세트마다 한 명씩 나간다 (3전 2선승, 플레이오프 5전 3선승).
public enum DuelLineupBuilder {
    /// 정규 시즌 한 경기에 나서는 선수 수 (세 세트, 한 명이 한 세트씩. 1 : 1이면 마지막 세트가 에이스 결정전이다).
    public static let setsPerMatch = 3

    /// 능력 순으로 세운 출전 순서. 맨 앞이 에이스다. 1:1 대전 선수가 세 명은 있어야 한다.
    public static func build(team: Team, players: [PlayerID: Player]) -> [PlayerID]? {
        let roster = team.roster.compactMap { players[$0] }.filter { $0.position.sport == .duel }
        guard roster.count >= setsPerMatch else { return nil }
        return roster.sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }.map(\.id)
    }

    /// 팀의 힘: 세트에 나설 세 명의 능력. 에이스가 마지막 세트에도 나가므로 조금 더 무겁다.
    public static func strength(team: Team, players: [PlayerID: Player]) -> Double {
        guard let order = build(team: team, players: players) else { return 0 }
        let top = order.prefix(setsPerMatch).compactMap { players[$0]?.ability }
        let weights = [0.4, 0.3, 0.3]
        return zip(top, weights).reduce(0) { $0 + $1.0 * $1.1 }
    }
}
