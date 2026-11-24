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

// MARK: 종목마다 다른 규칙
//
// 여러 곳에서 같은 뜻으로 갈라지는 규칙은 여기에 이름을 붙여 모은다. 모두 빠짐없는 switch라서
// 새 종목을 넣으면 컴파일러가 여기부터 하나하나 정하라고 알려 준다.

extension Sport {
    /// 순위를 승점(승 3, 무 1)으로 매긴다. 아니면 승률로 매긴다.
    public var ranksByPoints: Bool {
        switch self {
        case .football: true
        case .baseball, .basketball: false
        }
    }

    /// 무승부가 있는 종목. 농구는 연장을 끝까지 해서 무승부가 없다 (순위표에 "무" 칸을 두지 않는다).
    public var hasDraws: Bool {
        switch self {
        case .baseball, .football: true
        case .basketball: false
        }
    }

    /// 잉글랜드식 승강: 여러 팀이 바로 오르고, 플레이오프는 아랫 리그 팀끼리, 내 구단은 구장 등급으로 승격한다.
    /// 아니면 야구식: 1위 승격, 와일드카드와 승강 플레이오프, 내 구단은 신청해서 승격한다.
    public var usesEnglishPromotion: Bool {
        switch self {
        case .football: true
        case .baseball, .basketball: false
        }
    }

    /// 선수를 포지션으로 나눈다 (라이벌, 맞교환, 훈련 방침, 선수가 모자란지).
    /// 야구는 투수와 야수로 나눈다.
    public var groupsByPosition: Bool {
        switch self {
        case .football, .basketball: true
        case .baseball: false
        }
    }

    /// 명성과 스카우트 관심이 오르기 시작하는 평점. 축구와 농구는 평점이 6점대에 몰려 있어 기준이 낮다.
    public var careerRatingBaseline: Double {
        switch self {
        case .baseball: 6.5
        case .football, .basketball: 6.3
        }
    }

    /// 기준을 넘긴 평점이 명성에 얼마나 크게 반영되는지. 평점이 6점대에 몰린 종목은 크게 반영한다.
    public var careerFameWeight: Double {
        switch self {
        case .baseball: 1.0
        case .football, .basketball: 2.0
        }
    }
}
