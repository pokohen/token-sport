import Foundation

/// CPU 구단 성향. 같은 리그 팀들의 색깔을 다르게 만든다.
public enum TeamStyle: String, Codable, CaseIterable, Sendable {
    case youth = "유망주 육성형"
    case veteran = "베테랑 선호형"
    case pitching = "투수력 중시형"
    case balanced = "균형형"

    public func label(_ sport: Sport) -> String {
        self == .pitching && sport != .baseball ? "수비 중시형" : rawValue
    }
}

/// 팀 훈련 방침: 네 가지 비중 (합이 1이 되게 정규화해서 쓴다).
public struct TrainingFocus: Codable, Equatable, Sendable {
    public var batting = 0.25
    public var pitching = 0.25
    public var defense = 0.25
    public var running = 0.25

    public init() {}

    public init(batting: Double, pitching: Double, defense: Double, running: Double) {
        self.batting = batting
        self.pitching = pitching
        self.defense = defense
        self.running = running
    }

    var normalized: TrainingFocus {
        let total = max(0.0001, batting + pitching + defense + running)
        return TrainingFocus(
            batting: batting / total, pitching: pitching / total,
            defense: defense / total, running: running / total)
    }

    /// 세부 능력치별 성장 강조 (기본 방침이면 모두 1).
    /// 축구에서는 네 칸을 공격(batting) · 패스(pitching) · 수비(defense) · 체력(running)으로 쓴다.
    func emphasis(for key: Attributes.Key, sport: Sport = .baseball) -> Double {
        let focus = normalized
        if sport != .baseball {
            switch key {
            case .shooting, .dribbling, .three: return focus.batting / 0.25
            case .passing: return focus.pitching / 0.25
            case .tackling, .keeping, .rebounding: return focus.defense / 0.25
            default: return focus.running / 0.25
            }
        }
        switch key {
        case .contact, .power, .eye: return focus.batting / 0.25
        case .fielding, .arm: return focus.defense / 0.25
        case .speed: return focus.running / 0.25
        default: return focus.pitching / 0.25
        }
    }
}

public struct Team: Codable, Identifiable, Equatable, Sendable {
    public let id: TeamID
    public var name: String
    public var city: String
    public var tier: LeagueTier
    public var isUser: Bool
    public var roster: [PlayerID]
    /// CPU 구단 자금. 내 구단 자금은 `FundsLedger`가 따로 맡는다.
    public var funds: Int
    public var trainingLevel: Int
    public var stadiumLevel: Int
    public var scoutLevel: Int
    public var fame: Double
    /// 맞춰주기: 리그 목표 평균에서 이 팀이 떨어져 있을 정도 (강팀 +, 약팀 −).
    public var targetOffset: Double
    public var style: TeamStyle
    /// 지금까지 치른 경기 수 (선발 투수 휴식 계산용).
    public var gamesPlayed: Int
    /// 연승이면 양수, 연패면 음수.
    public var streak: Int
    public var colorIndex: Int
    public var emblemIndex: Int
    /// 내가 직접 정한 타순 (9명). 비어 있거나 맞지 않으면 자동으로 짠다.
    public var lineupOverride: [PlayerID]
    /// 다음 경기 선발로 지정한 투수.
    public var starterOverride: PlayerID?
    public var policy: PitchingPolicy
    public var focus: TrainingFocus
    /// 축구 전술 성향. 야구 구단과 예전 저장 파일에는 없다.
    public var tactic: Tactic? = nil
    /// 축구 포메이션. nil이면 4-4-2.
    public var formation: Formation? = nil
    /// 선발이 내려가면 가장 먼저 올릴 불펜 투수 (선수 모드의 내 선수). 보통은 nil.
    public var firstReliever: PlayerID? = nil
    /// 이 구단이 만들어진 시즌.
    public var foundedSeason: Int

    public var shortName: String { NameGenerator.shortName(name) }

    public init(id: TeamID, name: String, city: String, tier: LeagueTier, isUser: Bool, season: Int) {
        self.id = id
        self.name = name
        self.city = city
        self.tier = tier
        self.isUser = isUser
        self.roster = []
        self.funds = 0
        self.trainingLevel = 1
        self.stadiumLevel = 1
        self.scoutLevel = 0
        self.fame = 0
        self.targetOffset = 0
        self.style = .balanced
        self.gamesPlayed = 0
        self.streak = 0
        self.colorIndex = 0
        self.emblemIndex = 0
        self.lineupOverride = []
        self.starterOverride = nil
        self.policy = PitchingPolicy()
        self.focus = TrainingFocus()
        self.foundedSeason = season
    }
}

/// 한 경기에 나서는 선수 구성.
public struct Lineup: Equatable, Sendable {
    /// 타순대로 (선수, 서는 자리).
    public var batters: [(id: PlayerID, position: Position)]
    public var starter: PlayerID
    /// 올릴 순서대로의 불펜. 마무리가 맨 뒤.
    public var bullpen: [PlayerID]

    public static func == (lhs: Lineup, rhs: Lineup) -> Bool {
        lhs.starter == rhs.starter && lhs.bullpen == rhs.bullpen
            && lhs.batters.map(\.id) == rhs.batters.map(\.id)
            && lhs.batters.map(\.position) == rhs.batters.map(\.position)
    }
}

public enum LineupBuilder {
    /// 타자로서의 값어치 (타순 정렬용).
    static func battingValue(_ player: Player) -> Double {
        player.attributes.contact * 0.4 + player.attributes.power * 0.35 + player.attributes.eye * 0.25
    }

    /// 능력 순으로 자동 구성한다. 내가 정한 타순·선발이 있고 쓸 수 있으면 그것을 따른다.
    public static func build(team: Team, players: [PlayerID: Player]) -> Lineup? {
        let roster = team.roster.compactMap { players[$0] }
        let batters = roster.filter { !$0.isPitcher }
        let pitchers = roster.filter { $0.isPitcher }
        guard batters.count >= 9, !pitchers.isEmpty else { return nil }

        // 야수 9명
        var chosen: [(id: PlayerID, position: Position)] = []
        let override = team.lineupOverride.compactMap { players[$0] }
            .filter { !$0.isPitcher && team.roster.contains($0.id) }
        if override.count == 9, Set(override.map(\.id)).count == 9 {
            chosen = assignPositions(override, keepOrder: true)
        } else {
            let best = pickNine(batters)
            chosen = assignPositions(best, keepOrder: false)
        }

        // 투수
        let starters = pitchers.filter { $0.position == .starter }
        let rest = Balance.starterRest(team.tier)
        var starter: Player?
        if let wanted = team.starterOverride, let player = pitchers.first(where: { $0.id == wanted }) {
            starter = player
        }
        if starter == nil {
            let rested = starters.filter { team.gamesPlayed - $0.lastStartGame > rest }
            starter = rested.max { ($0.ability, -$0.id) < ($1.ability, -$1.id) }
                ?? starters.min { ($0.lastStartGame, $0.id) < ($1.lastStartGame, $1.id) }
                ?? pitchers.max { ($0.ability, -$0.id) < ($1.ability, -$1.id) }
        }
        guard let starter else { return nil }

        var relievers = pitchers
            .filter { $0.id != starter.id && $0.position == .reliever }
            .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
        if let first = team.firstReliever, let index = relievers.firstIndex(where: { $0.id == first }) {
            relievers.insert(relievers.remove(at: index), at: 0)
        }
        // 직전 경기에 많이 던졌거나 연투한 불펜은 맨 뒤로 보낸다 (꼭 필요할 때만 나온다).
        let tired = relievers.filter { $0.needsReliefRest(game: team.gamesPlayed) }
        if !tired.isEmpty, tired.count < relievers.count {
            relievers = relievers.filter { !$0.needsReliefRest(game: team.gamesPlayed) } + tired
        }
        let closers = pitchers.filter { $0.id != starter.id && $0.position == .closer }
        var bullpen = relievers.map(\.id) + closers.prefix(1).map(\.id)
        if bullpen.isEmpty {
            // 불펜이 없으면 가장 오래 쉰 다른 선발이 뒤를 받친다.
            bullpen = starters.filter { $0.id != starter.id }
                .sorted { ($0.lastStartGame, $0.id) < ($1.lastStartGame, $1.id) }
                .prefix(1).map(\.id)
        }
        return Lineup(batters: chosen, starter: starter.id, bullpen: bullpen)
    }

    /// 포지션을 다 채우면서 가장 잘 치는 9명을 고른다.
    private static func pickNine(_ batters: [Player]) -> [Player] {
        var remaining = batters.sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
        var nine: [Player] = []
        for position in Position.fieldPositions {
            if let index = remaining.firstIndex(where: { $0.position == position }) {
                nine.append(remaining.remove(at: index))
            }
        }
        remaining.sort { (battingValue($0), -$0.id) > (battingValue($1), -$1.id) }
        while nine.count < 9, !remaining.isEmpty {
            nine.append(remaining.removeFirst())
        }
        return nine
    }

    /// 9명에게 자리를 나눠 준다. 제 포지션이 아닌 곳에 서면 경기에서 수비가 깎인다.
    private static func assignPositions(_ nine: [Player], keepOrder: Bool) -> [(id: PlayerID, position: Position)] {
        var open = Position.fieldPositions
        var assigned: [PlayerID: Position] = [:]
        for player in nine where open.contains(player.position) {
            assigned[player.id] = player.position
            open.removeAll { $0 == player.position }
        }
        // 남은 선수 중 타격이 가장 좋은 선수가 지명타자, 나머지는 빈 자리를 메운다.
        var unassigned = nine.filter { assigned[$0.id] == nil }
            .sorted { (battingValue($0), -$0.id) > (battingValue($1), -$1.id) }
        if open.count < unassigned.count, !unassigned.isEmpty {
            assigned[unassigned.removeFirst().id] = .designated
        }
        for player in unassigned {
            assigned[player.id] = open.isEmpty ? .designated : open.removeFirst()
        }
        let order = keepOrder
            ? nine
            : nine.sorted { (battingValue($0), -$0.id) > (battingValue($1), -$1.id) }
        return order.map { ($0.id, assigned[$0.id] ?? .designated) }
    }

    /// 경기 엔진에 넘길 팀 구성.
    public static func matchTeam(team: Team, players: [PlayerID: Player]) -> MatchTeam? {
        guard let lineup = build(team: team, players: players) else { return nil }
        let batters: [MatchBatter] = lineup.batters.compactMap { entry in
            guard let player = players[entry.id] else { return nil }
            let outOfPosition = entry.position != .designated && entry.position != player.position
            let hot = player.isHot ? 3.0 : 0.0
            return MatchBatter(
                playerID: player.id, name: player.name, position: entry.position,
                contact: player.attributes.contact + hot, power: player.attributes.power,
                eye: player.attributes.eye, speed: player.attributes.speed,
                fielding: player.attributes.fielding - (outOfPosition ? 12 : 0),
                arm: player.attributes.arm, bats: player.bats, traits: player.traits)
        }
        let pitchers: [MatchPitcher] = ([lineup.starter] + lineup.bullpen).enumerated().compactMap { index, id in
            guard let player = players[id] else { return nil }
            let hot = player.isHot ? 3.0 : 0.0
            return MatchPitcher(
                playerID: player.id, name: player.name,
                role: index == 0 ? .starter : (player.position == .starter ? .reliever : player.position),
                stuff: player.attributes.stuff + hot, control: player.attributes.control,
                breaking: player.attributes.breaking, stamina: player.attributes.stamina,
                throwsHand: player.throwsHand, traits: player.traits)
        }
        guard batters.count == 9, !pitchers.isEmpty else { return nil }
        return MatchTeam(
            teamID: team.id, name: team.name, shortName: team.shortName,
            batters: batters, pitchers: pitchers, policy: team.policy)
    }

    /// 팀 강도 = 주전 라인업 + 선발 투수진의 평균 능력.
    public static func strength(team: Team, players: [PlayerID: Player]) -> Double {
        let roster = team.roster.compactMap { players[$0] }
        let batters = roster.filter { !$0.isPitcher }.map(\.ability).sorted(by: >).prefix(9)
        let starters = roster.filter { $0.position == .starter }.map(\.ability)
        let all = Array(batters) + starters
        return all.isEmpty ? 0 : all.reduce(0, +) / Double(all.count)
    }
}
