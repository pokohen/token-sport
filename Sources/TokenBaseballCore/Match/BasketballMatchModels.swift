import Foundation

/// 농구 경기에 나선 선수 한 명. 능력치는 경기를 시작할 때의 값이고, 체력(`energy`)에 따라 깎여 쓰인다.
public struct BasketballPlayerState: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    public var name: String
    /// 원래 포지션.
    public var natural: Position
    /// 이 경기에서 서는 자리.
    public var slot: Position
    public var shooting: Double, three: Double, passing: Double, dribbling: Double
    public var defense: Double, rebounding: Double, speed: Double, physical: Double, stamina: Double
    public var traits: [Trait]
    /// 남은 체력 (1 = 가득).
    public var energy = 1.0
    public var isOnCourt: Bool
    public var hasPlayed: Bool
    public var isStarter: Bool
    /// 다섯 번째 반칙으로 물러났는지.
    public var fouledOut = false
    public var line = BasketballLine()
    /// 선수 모드에서 고른 플레이 스타일. 내 선수에게만 있다.
    public var style: PlayStyle? = nil

    public init(
        playerID: PlayerID, name: String, natural: Position, slot: Position,
        shooting: Double, three: Double, passing: Double, dribbling: Double,
        defense: Double, rebounding: Double, speed: Double, physical: Double, stamina: Double,
        traits: [Trait], starts: Bool
    ) {
        self.playerID = playerID
        self.name = name
        self.natural = natural
        self.slot = slot
        self.shooting = shooting
        self.three = three
        self.passing = passing
        self.dribbling = dribbling
        self.defense = defense
        self.rebounding = rebounding
        self.speed = speed
        self.physical = physical
        self.stamina = stamina
        self.traits = traits
        self.isOnCourt = starts
        self.hasPlayed = starts
        self.isStarter = starts
        if starts {
            line.games = 1
            line.starts = 1
        }
    }

    /// 지치면 모든 능력이 조금씩 깎인다.
    var fatigue: Double { 0.8 + 0.2 * energy }
}

public struct BasketballSide: Codable, Equatable, Sendable {
    public var teamID: TeamID
    public var name: String
    public var shortName: String
    /// 앞의 다섯 명이 선발, 나머지가 벤치.
    public var players: [BasketballPlayerState]
    public var points = 0
    /// 쿼터별 득점 (연장은 뒤에 이어 붙는다).
    public var pointsByPeriod: [Int] = []
    /// 선수 모드: 벤치에서 시작한 내 선수. 정해진 시간만큼은 반드시 뛴다.
    public var featured: PlayerID? = nil
    /// 그 선수가 정규 시간 40분 가운데 뛰어야 하는 시간(분).
    public var featuredMinutes: Int? = nil

    public init(teamID: TeamID, name: String, shortName: String, players: [BasketballPlayerState]) {
        self.teamID = teamID
        self.name = name
        self.shortName = shortName
        self.players = players
    }

    var onCourt: [Int] { players.indices.filter { players[$0].isOnCourt } }

    /// 코트 위 다섯 명의 평균.
    func mean(_ value: (BasketballPlayerState) -> Double) -> Double {
        let five = onCourt
        guard !five.isEmpty else { return 10 }
        return five.reduce(0) { $0 + value(players[$1]) * players[$1].fatigue } / Double(five.count)
    }

    /// 팀 기록: 선수 기록을 더한 값.
    public var totals: BasketballLine {
        var line = BasketballLine()
        for player in players { line += player.line }
        return line
    }
}

public struct BasketballRules: Codable, Equatable, Sendable {
    /// 홈 보정 (0.02 = 슛 성공률 +1.5%쯤).
    public var homeEdge = 0.02
    /// 중립 구장: 홈 이점이 없다.
    public var neutral: Bool? = nil

    public init(homeEdge: Double = 0.02) {
        self.homeEdge = homeEdge
    }
}
