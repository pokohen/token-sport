import Foundation

/// 선수 모드에서 평점을 매기려고 내 선수에게만 남기는 세부 기록.
public struct FootballDetail: Codable, Equatable, Sendable {
    /// 경기장에 있던 틱 수 (한 틱 = 경기 시간 20초).
    public var ticks = 0
    /// 공을 앞으로 운반한 횟수 (우리 진영 → 중원, 중원 → 상대 진영).
    public var advances = 0
    /// 공을 뺏어낸 횟수.
    public var tackles = 0
    /// 걷어내거나 슈팅을 몸으로 막은 횟수.
    public var clearances = 0
    public var fouls = 0

    public init() {}

    public var minutes: Int { ticks * FootballMatch.secondsPerStep / 60 }
}

/// 선수 모드에서 경기 전에 고르는 플레이 스타일.
public enum PlayStyle: String, Codable, CaseIterable, Sendable {
    case balanced = "균형", greedy = "욕심내기", link = "연계", defensive = "수비 가담"

    /// 슈팅을 가져갈 가능성에 곱하는 값.
    var shotWeight: Double {
        switch self {
        case .greedy: 1.7
        case .link: 0.65
        case .defensive: 0.75
        case .balanced: 1
        }
    }

    /// 도움을 줄 가능성에 곱하는 값.
    var assistWeight: Double {
        switch self {
        case .greedy: 0.55
        case .link: 1.7
        case .defensive: 0.9
        case .balanced: 1
        }
    }

    /// 공을 뺏거나 걷어내는 장면에 나설 가능성에 곱하는 값.
    var defenseWeight: Double { self == .defensive ? 2 : self == .greedy ? 0.6 : 1 }

    /// 체력이 줄어드는 속도에 곱하는 값.
    var drain: Double { self == .defensive ? 1.2 : 1 }

    /// 농구에서의 설명.
    public var basketballSummary: String {
        switch self {
        case .balanced: "특별한 효과가 없습니다."
        case .greedy: "슛을 더 많이 던집니다. 무리한 슛이 섞여 성공률이 조금 떨어지고, 도움과 수비 가담이 줄어듭니다."
        case .link: "도움 기회가 늘고 슛이 줄어듭니다. 도움 하나가 평점에 더 크게 반영됩니다."
        case .defensive: "스틸, 블록, 리바운드에 더 자주 나서지만 체력이 빨리 줄고 슛이 줄어듭니다."
        }
    }

    public var summary: String {
        switch self {
        case .balanced: "특별한 효과가 없습니다."
        case .greedy: "슈팅을 더 많이 가져갑니다. 도움과 수비 가담이 줄어듭니다."
        case .link: "도움 기회가 늘고 슈팅이 줄어듭니다."
        case .defensive: "공을 뺏고 걷어내는 장면이 늘지만 체력이 빨리 줄고 슈팅이 줄어듭니다."
        }
    }
}

/// 축구 경기에 나선 선수 한 명. 능력치는 경기를 시작할 때의 값이고, 체력(`energy`)에 따라 깎여 쓰인다.
public struct FootballPlayerState: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    public var name: String
    /// 원래 포지션.
    public var natural: Position
    /// 이 경기에서 서는 자리.
    public var slot: Position
    public var shooting: Double, passing: Double, dribbling: Double, tackling: Double
    public var speed: Double, physical: Double, keeping: Double, stamina: Double
    public var traits: [Trait]
    /// 남은 체력 (1 = 가득).
    public var energy = 1.0
    public var isOnPitch: Bool
    public var hasPlayed: Bool
    public var sentOff = false
    public var line = FootballLine()
    /// 선수 모드의 내 선수에게만 있다.
    public var detail: FootballDetail? = nil
    public var style: PlayStyle? = nil

    public init(
        playerID: PlayerID, name: String, natural: Position, slot: Position,
        shooting: Double, passing: Double, dribbling: Double, tackling: Double,
        speed: Double, physical: Double, keeping: Double, stamina: Double,
        traits: [Trait], starts: Bool
    ) {
        self.playerID = playerID
        self.name = name
        self.natural = natural
        self.slot = slot
        self.shooting = shooting
        self.passing = passing
        self.dribbling = dribbling
        self.tackling = tackling
        self.speed = speed
        self.physical = physical
        self.keeping = keeping
        self.stamina = stamina
        self.traits = traits
        self.isOnPitch = starts
        self.hasPlayed = starts
        if starts { line.games = 1 }
    }

    /// 지치면 모든 능력이 조금씩 깎인다.
    var fatigue: Double { 0.75 + 0.25 * energy }
}

public struct FootballSide: Codable, Equatable, Sendable {
    public var teamID: TeamID
    public var name: String
    public var shortName: String
    /// 앞의 11명이 선발, 나머지가 벤치.
    public var players: [FootballPlayerState]
    public var tactic: Tactic
    /// nil이면 4-4-2 (이 값이 없던 때의 저장 파일도 그렇게 읽는다).
    public var formation: Formation?
    public var goals = 0
    public var shots = 0, shotsOnTarget = 0, corners = 0, fouls = 0, offsides = 0
    public var yellowCards = 0, redCards = 0
    /// 공을 갖고 있던 틱 수 (점유율 계산용).
    public var possession = 0
    public var subsUsed = 0
    public var shootoutGoals = 0, shootoutKicks = 0
    /// 선수 모드: 이 시간(분)이 되면 반드시 교체로 들어갈 벤치 선수.
    public var guaranteedSub: PlayerID? = nil
    public var guaranteedMinute: Int? = nil

    public init(teamID: TeamID, name: String, shortName: String, players: [FootballPlayerState], tactic: Tactic,
        formation: Formation? = nil
    ) {
        self.teamID = teamID
        self.name = name
        self.shortName = shortName
        self.players = players
        self.tactic = tactic
        self.formation = formation
    }

    public var shape: Formation { formation ?? .f442 }

    var onPitchCount: Int { players.filter(\.isOnPitch).count }

    /// 해당 자리에 선 선수들의 평균. 아무도 없으면 아주 낮은 값.
    func mean(
        _ slots: [Position], weights: [Position: Double] = [:], _ value: (FootballPlayerState) -> Double
    ) -> Double {
        var total = 0.0, weight = 0.0
        for player in players where player.isOnPitch && slots.contains(player.slot) {
            let w = weights[player.slot] ?? 1
            total += value(player) * player.fatigue * w
            weight += w
        }
        return weight > 0 ? total / weight : 10
    }

    /// 퇴장으로 모자란 인원만큼 깎이는 값.
    var shortHanded: Double { Double(max(0, 11 - onPitchCount)) * 8 }

    var keeperIndex: Int? { players.firstIndex { $0.isOnPitch && $0.slot == .goalkeeper } }
}

public struct FootballRules: Codable, Equatable, Sendable {
    /// 승부가 나야 하는 경기 (승강 플레이오프): 연장과 승부차기를 쓴다.
    public var mustHaveWinner = false
    /// 홈 보정 (0.02 = +2%).
    public var homeEdge = 0.02
    /// 중립 구장 (승격 플레이오프 결승): 홈 이점이 없다.
    public var neutral: Bool? = nil
    /// 두 경기 합산의 2차전: 1차전에서 이 경기의 (홈 팀, 원정 팀)이 넣은 골. 합산이 같으면 연장으로 간다.
    public var firstLegHome: Int? = nil
    public var firstLegAway: Int? = nil

    public init(mustHaveWinner: Bool = false, homeEdge: Double = 0.02) {
        self.mustHaveWinner = mustHaveWinner
        self.homeEdge = homeEdge
    }
}
