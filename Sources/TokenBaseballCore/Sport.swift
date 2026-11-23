import Foundation

/// 종목. 구단을 만들 때 고르고, 세이브는 종목별로 따로 둔다.
public enum Sport: String, Codable, CaseIterable, Sendable {
    case baseball, football, basketball

    public var label: String {
        switch self {
        case .baseball: "야구"
        case .football: "축구"
        case .basketball: "농구"
        }
    }

    public var symbol: String {
        switch self {
        case .baseball: "⚾"
        case .football: "⚽"
        case .basketball: "🏀"
        }
    }

    /// 한 경기에 나서는 선수 수 (야구는 야수 9명 + 투수).
    public var clubWord: String {
        switch self {
        case .baseball: "야구단"
        case .football: "축구단"
        case .basketball: "농구단"
        }
    }
}

/// 농구 선수의 시즌 기록 (경기 중에는 그 경기의 기록).
public struct BasketballLine: Codable, Equatable, Sendable {
    public var games = 0, starts = 0
    /// 뛴 시간(초).
    public var seconds = 0
    public var points = 0, rebounds = 0, assists = 0, steals = 0, blocks = 0, turnovers = 0, fouls = 0
    public var fieldGoalsMade = 0, fieldGoalsAttempted = 0
    public var threesMade = 0, threesAttempted = 0
    public var freeThrowsMade = 0, freeThrowsAttempted = 0

    public init() {}

    public var minutes: Int { seconds / 60 }
    public var pointsPerGame: Double { games == 0 ? 0 : Double(points) / Double(games) }
    public var reboundsPerGame: Double { games == 0 ? 0 : Double(rebounds) / Double(games) }
    public var assistsPerGame: Double { games == 0 ? 0 : Double(assists) / Double(games) }
    public var minutesPerGame: Double { games == 0 ? 0 : Double(seconds) / 60 / Double(games) }
    public var fieldGoalRate: Double {
        fieldGoalsAttempted == 0 ? 0 : Double(fieldGoalsMade) / Double(fieldGoalsAttempted)
    }
    public var threeRate: Double { threesAttempted == 0 ? 0 : Double(threesMade) / Double(threesAttempted) }
    /// 두 자릿수 기록이 둘 이상이면 더블더블 (득점, 리바운드, 어시스트, 스틸, 블록 가운데).
    public var isDoubleDouble: Bool {
        [points, rebounds, assists, steals, blocks].filter { $0 >= 10 }.count >= 2
    }

    public static func += (lhs: inout BasketballLine, rhs: BasketballLine) {
        lhs.games += rhs.games
        lhs.starts += rhs.starts
        lhs.seconds += rhs.seconds
        lhs.points += rhs.points
        lhs.rebounds += rhs.rebounds
        lhs.assists += rhs.assists
        lhs.steals += rhs.steals
        lhs.blocks += rhs.blocks
        lhs.turnovers += rhs.turnovers
        lhs.fouls += rhs.fouls
        lhs.fieldGoalsMade += rhs.fieldGoalsMade
        lhs.fieldGoalsAttempted += rhs.fieldGoalsAttempted
        lhs.threesMade += rhs.threesMade
        lhs.threesAttempted += rhs.threesAttempted
        lhs.freeThrowsMade += rhs.freeThrowsMade
        lhs.freeThrowsAttempted += rhs.freeThrowsAttempted
    }
}

/// 축구 전술 성향. 슈팅 기회와 실점 위험이 함께 오르내린다.
public enum Tactic: String, Codable, CaseIterable, Sendable {
    case attacking = "공격적", balanced = "균형", defensive = "수비적"

    /// 공격 쪽 능력에 더하는 값. 수비 쪽에는 같은 크기를 뺀다.
    var attackShift: Double {
        switch self {
        case .attacking: 4
        case .balanced: 0
        case .defensive: -4
        }
    }
}

/// 축구 포메이션. 줄마다 서는 인원이 달라지고, 강한 곳과 약한 곳이 생긴다.
public enum Formation: String, Codable, CaseIterable, Sendable {
    case f442 = "4-4-2", f433 = "4-3-3", f4231 = "4-2-3-1", f41212 = "4-1-2-1-2"
    case f352 = "3-5-2", f343 = "3-4-3", f532 = "5-3-2"

    public var label: String { rawValue }

    /// 수비, 미드필더, 공격 인원.
    public var shape: (defenders: Int, midfielders: Int, forwards: Int) {
        switch self {
        case .f442, .f41212: (4, 4, 2)
        case .f433: (4, 3, 3)
        case .f4231: (4, 5, 1)
        case .f352: (3, 5, 2)
        case .f343: (3, 4, 3)
        case .f532: (5, 3, 2)
        }
    }

    /// 열한 자리. 골키퍼 → 수비 → 미드필더 → 공격 순.
    public var slots: [Position] {
        let s = shape
        return [.goalkeeper] + Array(repeating: .defender, count: s.defenders)
            + Array(repeating: .midfielder, count: s.midfielders) + Array(repeating: .forward, count: s.forwards)
    }

    /// 중원 싸움에 더하는 값 (공격할 때도 수비할 때도).
    var midfieldShift: Double {
        switch self {
        case .f433: -2
        case .f4231: 2
        case .f41212: 2
        case .f352: 3
        case .f532: -2
        case .f442, .f343: 0
        }
    }

    /// 상대 진영에서 기회를 만들 때 더하는 값.
    var attackShift: Double {
        switch self {
        case .f433: 3
        case .f4231: -4
        case .f343: 5
        default: 0
        }
    }

    /// 우리 진영에서 막을 때 더하는 값.
    var defenseShift: Double {
        switch self {
        case .f41212: -5
        case .f352: -6
        case .f343: -5
        case .f532: 4
        default: 0
        }
    }

    public var summary: String {
        switch self {
        case .f442: "기본형. 강한 곳도 약한 곳도 없습니다."
        case .f433: "공격수 3명. 상대 진영에서 기회를 더 만들지만 중원 싸움에서 밀립니다."
        case .f4231: "미드필더 5명에 원톱. 중원을 잡지만 상대 진영에서 기회가 줄어듭니다."
        case .f41212: "다이아몬드 중원. 중원을 장악하지만 측면이 비어 우리 진영 수비가 약해집니다."
        case .f352: "수비수 3명에 미드필더 5명. 중원이 가장 강하지만 우리 진영 수비가 가장 약합니다."
        case .f343: "수비수 3명에 공격수 3명. 기회를 가장 많이 만들지만 뒤가 열립니다."
        case .f532: "수비수 5명. 우리 진영 수비가 단단하지만 중원 싸움에서 밀립니다."
        }
    }
}

/// 축구 선수의 시즌 기록 (경기 중에는 그 경기의 기록).
public struct FootballLine: Codable, Equatable, Sendable {
    public var games = 0, goals = 0, assists = 0
    public var shots = 0, shotsOnTarget = 0
    public var yellowCards = 0, redCards = 0
    /// 골키퍼 기록.
    public var saves = 0, conceded = 0, cleanSheets = 0

    public init() {}

    public var points: Int { goals + assists }

    public static func += (lhs: inout FootballLine, rhs: FootballLine) {
        lhs.games += rhs.games
        lhs.goals += rhs.goals
        lhs.assists += rhs.assists
        lhs.shots += rhs.shots
        lhs.shotsOnTarget += rhs.shotsOnTarget
        lhs.yellowCards += rhs.yellowCards
        lhs.redCards += rhs.redCards
        lhs.saves += rhs.saves
        lhs.conceded += rhs.conceded
        lhs.cleanSheets += rhs.cleanSheets
    }
}
