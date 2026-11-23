import Foundation

/// CPU 팀 맞춰주기 강도.
public enum RubberBand: String, Codable, CaseIterable, Sendable {
    case off = "끄기", weak = "약하게", normal = "보통", strong = "강하게"

    /// 성장 속도 보정 폭.
    var growthSwing: Double {
        switch self {
        case .off: 0
        case .weak: 0.10
        case .normal: 0.15
        case .strong: 0.25
        }
    }

    /// 시즌당 리그 평균 상승 한도.
    var seasonCap: Double {
        switch self {
        case .off: 0
        case .weak: 2
        case .normal: 3
        case .strong: 5
        }
    }

    /// 영입 보정을 하는지.
    var adjustsRecruiting: Bool { self == .normal || self == .strong }
}

/// 상단바에 보일 숫자.
public enum MenuBarDisplay: String, Codable, CaseIterable, Sendable {
    case funds = "구단 자금", today = "오늘 사용량", nextMatch = "다음 경기"
}

public struct Settings: Codable, Equatable, Sendable {
    public var rubberBand = RubberBand.normal
    /// 가격 난이도 (0.1 ~ 2.0). 비용에만 곱한다. 토큰 수는 건드리지 않는다.
    public var priceDifficulty = 1.0
    public var menuBarDisplay = MenuBarDisplay.funds
    public var animationEnabled = true
    public var notificationsEnabled = true
    /// 선수 모드: 정해진 횟수를 넘겨서도 (더 비싼 값에) 훈련할 수 있는지. 꺼져 있으면 경기 사이에 정해진 횟수까지만 한다.
    /// (예전 저장 파일에는 없어서 Optional이다. 없으면 꺼짐.)
    public var extraTraining: Bool?

    public init() {}
}

public struct NewsItem: Codable, Equatable, Identifiable, Sendable {
    public var id: Int
    public var season: Int
    public var text: String
}

public enum SeasonPhase: String, Codable, Sendable {
    case regular, playoff, offseason
}

/// 플레이오프의 한 대진. 형식에 따라 한 경기일 수도, 여러 경기일 수도 있다.
/// (형식과 단계가 없는 예전 저장 파일은 3전 2선승의 승강 플레이오프로 읽는다.)
public struct PlayoffSeries: Codable, Equatable, Sendable {
    public enum Format: String, Codable, Sendable {
        /// 3전 2선승 (1·3차전은 `upperTeam` 홈).
        case bestOfThree
        /// 승격 와일드카드: 순위가 높은 팀(`upperTeam`) 홈에서, 그 팀은 1승·상대는 2연승이 필요하다.
        case wildcard
        /// 홈·원정 두 경기 합산 (1차전은 `lowerTeam` 홈).
        case twoLegs
        /// 중립 구장 단판.
        case single
    }

    public enum Stage: String, Codable, Sendable {
        case wildcard, semi, final, promotion
    }

    /// 이 대진이 걸린 리그 경계의 윗 리그.
    public var upperTier: LeagueTier
    /// 승강 플레이오프에서는 윗 리그 팀, 그 밖에는 정규시즌 순위가 높은 팀.
    public var upperTeam: TeamID
    public var lowerTeam: TeamID
    public var upperWins = 0
    public var lowerWins = 0
    public var format: Format? = nil
    public var stage: Stage? = nil
    /// 두 경기 합산: 지금까지의 골과 치른 경기 수.
    public var upperGoals: Int? = nil
    public var lowerGoals: Int? = nil
    public var legs: Int? = nil

    public var gamesPlayed: Int { upperWins + lowerWins }
}

/// 리그 이동 예정.
public struct TierMove: Codable, Equatable, Sendable {
    public var team: TeamID
    public var to: LeagueTier
}

public enum MatchKind: String, Codable, Sendable {
    case regular, playoff, friendly
    /// 컵대회 (선수 모드). 단판이고 반드시 승부가 난다.
    case cup

    public var label: String {
        switch self {
        case .regular: "정규시즌"
        case .playoff: "승강 플레이오프"
        case .friendly: "친선 경기"
        case .cup: "컵대회"
        }
    }
}

/// 진행 중인 내 경기와, 같은 라운드의 내 리그 다른 경기들.
public struct LiveMatch: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var state: MatchState
    public var others: [MatchState]
    public var userIsHome: Bool
    public var tier: LeagueTier
}

/// 진행 중인 내 축구 경기와, 같은 라운드의 내 리그 다른 경기들.
public struct LiveFootballMatch: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var state: FootballMatch
    public var others: [FootballMatch]
    public var userIsHome: Bool
    public var tier: LeagueTier
}

/// 진행 중인 내 농구 경기와, 같은 라운드의 내 리그 다른 경기들.
public struct LiveBasketballMatch: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var state: BasketballMatch
    public var others: [BasketballMatch]
    public var userIsHome: Bool
    public var tier: LeagueTier
}

/// 끝난 내 경기 결과. 상단바의 "경기 종료" 표시에 쓴다.
public struct LastResult: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var myRuns: Int
    public var theirRuns: Int
    public var opponent: String
    public var wasHome: Bool
    /// 팝오버를 열어 확인했는지.
    public var acknowledged = false
    public var summary: [String]
    /// 승부차기로 끝난 경기: 내가 이겼는지. 그 밖에는 nil.
    public var shootoutWon: Bool? = nil

    public var label: String {
        if let shootoutWon { return "\(shootoutWon ? "승" : "패") \(myRuns):\(theirRuns) 승부차기" }
        return myRuns > theirRuns ? "승 \(myRuns):\(theirRuns)" : myRuns < theirRuns ? "패 \(myRuns):\(theirRuns)" : "무 \(myRuns):\(theirRuns)"
    }
}

public struct AwardRecord: Codable, Equatable, Sendable {
    public var season: Int
    public var tier: LeagueTier
    public var title: String
    public var playerName: String
    public var teamName: String
    public var detail: String
    public var isMine: Bool
}

/// 해체된 구단의 기록 (명예의 전당).
public struct HallEntry: Codable, Equatable, Sendable {
    public var name: String
    public var foundedSeason: Int
    public var endedSeason: Int
    public var bestTier: LeagueTier
    public var star: String?
}

public struct GameError: Error, Equatable, CustomStringConvertible, Sendable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var description: String { message }
}
