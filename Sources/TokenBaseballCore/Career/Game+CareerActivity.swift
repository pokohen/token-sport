import Foundation

/// 선수 모드: 경기장 밖 활동. 훈련 포인트를 들여 명성을 올린다.
public enum CareerActivity: String, CaseIterable, Codable, Sendable {
    case fanMeeting
    case interview
    case youthClinic

    public var label: String {
        switch self {
        case .fanMeeting: "팬 사인회"
        case .interview: "지역 방송 인터뷰"
        case .youthClinic: "유소년 교실 봉사"
        }
    }

    public var detail: String {
        switch self {
        case .fanMeeting: "경기장 앞에서 팬들을 만난다."
        case .interview: "지역 방송에 나가 얼굴을 알린다."
        case .youthClinic: "동네 아이들을 가르친다. 감독도 좋게 본다 (감독 신뢰 +1)."
        }
    }

    /// 드는 훈련 포인트 (가격 난이도를 곱하기 전).
    public var cost: Int {
        switch self {
        case .fanMeeting: 1_500_000
        case .interview: 4_000_000
        case .youthClinic: 8_000_000
        }
    }

    /// 명성이 0일 때 오르는 양. 지금 리그의 명성 한도에 가까울수록 덜 오른다.
    public var fame: Double {
        switch self {
        case .fanMeeting: 1.0
        case .interview: 2.5
        case .youthClinic: 4.0
        }
    }

    public var trust: Double { self == .youthClinic ? 1 : 0 }
}

extension Game {
    public func careerActivityCost(_ activity: CareerActivity) -> Int { price(activity.cost) }

    /// 지금 하면 실제로 오르는 명성. 경기로 얻는 명성과 같은 규칙으로, 리그의 한도에 가까울수록 줄어든다.
    public func careerActivityGain(_ activity: CareerActivity) -> Double {
        guard let career, !career.isFreeAgent else { return 0 }
        let cap = Balance.careerFameCap(userTier)
        guard career.fame < cap else { return 0 }
        return min(cap - career.fame, activity.fame * (cap - career.fame) / cap)
    }

    /// 지금 이 활동을 할 수 없는 이유. 할 수 있으면 nil.
    public func careerActivityBlockedReason(_ activity: CareerActivity) -> String? {
        guard let career, !career.retired, players[career.playerID] != nil else { return "선수가 없습니다." }
        if career.isFreeAgent { return "소속 구단이 있어야 합니다." }
        if career.activityDone == true { return "다음 경기를 치르면 다시 할 수 있습니다." }
        if career.fame >= Balance.careerFameCap(userTier) {
            return "지금 리그에서는 명성이 더 오르지 않습니다. 윗 리그로 올라가야 합니다."
        }
        let cost = careerActivityCost(activity)
        if let reason = insufficientFundsReason(cost) { return reason }
        return nil
    }

    /// 명성 활동을 한다. 경기와 경기 사이에 한 번.
    public mutating func doCareerActivity(_ activity: CareerActivity) throws {
        if let reason = careerActivityBlockedReason(activity) { throw GameError(reason) }
        guard var career else { return }
        let gain = careerActivityGain(activity)
        funds.spend(careerActivityCost(activity), .promotion)
        career.fame += gain
        career.trust = min(100, career.trust + activity.trust)
        career.activityDone = true
        self.career = career
    }

    /// 내 선수의 이름을 바꾼다. 지난 시즌 기록과 구단 이력은 그대로다.
    public mutating func renameCareerPlayer(to newName: String) throws {
        guard let career, !career.retired, var me = players[career.playerID] else { throw GameError("선수가 없습니다.") }
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GameError("선수 이름을 입력해 주세요.") }
        guard name.count <= 12 else { throw GameError("이름은 12자까지입니다.") }
        me.name = name
        players[me.id] = me
    }
}
