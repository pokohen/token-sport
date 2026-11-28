import Foundation

/// 6부 리그. 숫자가 작을수록 상위 리그다.
public enum LeagueTier: Int, Codable, CaseIterable, Comparable, Sendable {
    case pro = 1
    case semiPro = 2
    case amateur = 3
    case citizenPro = 4
    case citizenSemiPro = 5
    case citizenAmateur = 6

    public static func < (lhs: LeagueTier, rhs: LeagueTier) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 배열에서 쓰는 위치 (1부 = 0).
    public var index: Int { rawValue - 1 }

    public var name: String {
        switch self {
        case .pro: "프로"
        case .semiPro: "세미프로"
        case .amateur: "아마추어"
        case .citizenPro: "시민 프로"
        case .citizenSemiPro: "시민 세미프로"
        case .citizenAmateur: "시민 아마추어"
        }
    }

    public var displayName: String { "\(rawValue)부 \(name)" }

    /// 종목에 맞는 리그 이름. e스포츠만 이름이 다르다 (→ docs/10-esports.md "리그").
    public func name(for sport: Sport) -> String {
        switch sport {
        case .baseball, .football, .basketball: name
        case .duel:
            switch self {
            case .pro: "프로 리그"
            case .semiPro: "챌린저 리그"
            case .amateur: "아카데미 리그"
            case .citizenPro: "대학·클럽 리그"
            case .citizenSemiPro: "지역 아마추어"
            case .citizenAmateur: "PC방 리그"
            }
        }
    }

    public func displayName(for sport: Sport) -> String { "\(rawValue)부 \(name(for: sport))" }

    /// 시민 리그(4~6부)인지.
    public var isCitizen: Bool { rawValue >= 4 }

    /// 한 단계 위 리그. 1부면 없음.
    public var upper: LeagueTier? { LeagueTier(rawValue: rawValue - 1) }
    /// 한 단계 아래 리그. 6부면 없음.
    public var lower: LeagueTier? { LeagueTier(rawValue: rawValue + 1) }
}
