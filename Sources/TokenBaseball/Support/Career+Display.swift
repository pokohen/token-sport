import TokenBaseballCore

// 선수 모드 화면의 이름: 컨디션, 입지, 목표, 재능, 훈련, 활동, 플레이 스타일, 기세, 칭호.

extension CareerCondition {
    var localizedLabel: String {
        switch self {
        case .best: String(localized: "최상")
        case .good: String(localized: "좋음")
        // 난이도 "보통"과 따로 옮길 수 있게 Condition 표에 둔다.
        case .normal: String(localized: "보통", table: "Condition")
        case .poor: String(localized: "나쁨")
        case .worst: String(localized: "최악")
        }
    }
}

extension CareerRole {
    var localizedName: String {
        switch self {
        case .starter: String(localized: "주전")
        case .rotation: String(localized: "주전 경쟁")
        // 재능 등급 "유망주"와 따로 옮길 수 있게 Role 표에 둔다.
        case .prospect: String(localized: "유망주", table: "Role")
        }
    }
}

extension CareerGoal {
    var localizedLabel: String {
        // 목표는 모두 1,000보다 작아서 자리 구분 쉼표가 붙지 않는다 (Core와 같은 글자).
        switch kind {
        case .hits: String(localized: "안타 \(target)개")
        case .homeRuns: String(localized: "홈런 \(target)개")
        case .wins: String(localized: "\(target)승")
        case .strikeouts: String(localized: "탈삼진 \(target)개")
        case .appearances: String(localized: "\(target)경기 등판")
        case .goals: String(localized: "\(target)골")
        case .points: String(localized: "공격 포인트 \(target)개 (골 + 도움)")
        case .cleanSheets: String(localized: "무실점 \(target)경기")
        case .matches: String(localized: "\(target)경기 출전")
        case .basketPoints: String(localized: "\(target)득점")
        case .rebounds: String(localized: "리바운드 \(target)개")
        case .assists: String(localized: "어시스트 \(target)개")
        case .setWins: String(localized: "세트 \(target)승")
        }
    }
}

extension CareerTalent {
    var localizedName: String {
        switch self {
        case .genius: String(localized: "천재")
        case .elite: String(localized: "특급 유망주")
        case .promising: String(localized: "유망주")
        case .ordinary: String(localized: "평범")
        case .lateBloomer: String(localized: "노력파")
        }
    }
}

extension CareerDrill {
    /// 능력치 하나를 올리는 훈련의 이름. Core의 `name(_:sport:)`과 같은 규칙이다.
    static func localizedName(_ key: Attributes.Key, sport: Sport) -> String {
        switch sport {
        case .football:
            switch key {
            case .shooting: return String(localized: "슈팅 연습")
            case .passing: return String(localized: "패스 훈련")
            case .dribbling: return String(localized: "드리블 훈련")
            case .tackling: return String(localized: "수비 훈련")
            case .speed: return String(localized: "스프린트")
            case .physical: return String(localized: "웨이트 트레이닝")
            case .keeping: return String(localized: "골키핑 훈련")
            case .stamina: return String(localized: "러닝")
            default: return key.localizedLabel
            }
        case .basketball:
            switch key {
            case .shooting: return String(localized: "미들슛 연습")
            case .three: return String(localized: "3점슛 연습")
            case .passing: return String(localized: "패스 훈련")
            case .dribbling: return String(localized: "드리블 훈련")
            case .tackling: return String(localized: "수비 훈련")
            case .rebounding: return String(localized: "박스아웃 훈련")
            case .speed: return String(localized: "속공 훈련")
            case .physical: return String(localized: "웨이트 트레이닝")
            case .stamina: return String(localized: "셔틀런")
            default: return key.localizedLabel
            }
        case .duel:
            switch key {
            case .control: return String(localized: "래더")
            case .macro: return String(localized: "빌드 반복 연습")
            case .strategy: return String(localized: "리플레이 분석")
            case .judgment: return String(localized: "연습 경기")
            case .mental: return String(localized: "멘탈 코칭")
            default: return key.localizedLabel
            }
        case .baseball:
            break
        }
        switch key {
        case .contact: return String(localized: "티 배팅")
        case .power: return String(localized: "웨이트 트레이닝")
        case .eye: return String(localized: "선구안 훈련")
        case .speed: return String(localized: "주루 훈련")
        case .fielding: return String(localized: "펑고")
        case .arm: return String(localized: "롱토스")
        case .stuff: return String(localized: "불펜 피칭")
        case .control: return String(localized: "제구 훈련")
        case .breaking: return String(localized: "변화구 연마")
        case .stamina: return String(localized: "러닝")
        default: return key.localizedLabel
        }
    }
}

extension CareerActivity {
    var localizedLabel: String {
        switch self {
        case .fanMeeting: String(localized: "팬 사인회")
        case .interview: String(localized: "지역 방송 인터뷰")
        case .youthClinic: String(localized: "유소년 교실 봉사")
        }
    }

    var localizedDetail: String {
        switch self {
        case .fanMeeting: String(localized: "경기장 앞에서 팬들을 만난다.")
        case .interview: String(localized: "지역 방송에 나가 얼굴을 알린다.")
        case .youthClinic: String(localized: "동네 아이들을 가르친다. 감독도 좋게 본다 (감독 신뢰 +1).")
        }
    }

    /// e스포츠에서의 이름: 팬 사인회 → 팬 미팅, 인터뷰 → 개인 방송, 유소년 교실 → 유망주 코칭.
    func localizedLabel(for sport: Sport) -> String {
        guard sport == .duel else { return localizedLabel }
        switch self {
        case .fanMeeting: return String(localized: "팬 미팅")
        case .interview: return String(localized: "개인 방송")
        case .youthClinic: return String(localized: "유망주 코칭")
        }
    }

    func localizedDetail(for sport: Sport) -> String {
        guard sport == .duel else { return localizedDetail }
        switch self {
        case .fanMeeting: return String(localized: "팬들을 만나 사인을 해 준다. 팬이 는다.")
        case .interview: return String(localized: "연습 장면을 방송한다. 팬이 조금 는다.")
        case .youthClinic: return String(localized: "어린 선수들을 가르친다. 팬이 많이 늘고, 운영과 판단이 조금 오른다.")
        }
    }
}

extension PlayStyle {
    var localizedName: String {
        switch self {
        case .balanced: String(localized: "균형")
        case .greedy: String(localized: "욕심내기")
        case .link: String(localized: "연계")
        case .defensive: String(localized: "수비 가담")
        }
    }

    var localizedSummary: String {
        switch self {
        case .balanced: String(localized: "특별한 효과가 없습니다.")
        case .greedy: String(localized: "슈팅을 더 많이 가져갑니다. 도움과 수비 가담이 줄어듭니다.")
        case .link: String(localized: "도움 기회가 늘고 슈팅이 줄어듭니다.")
        case .defensive: String(localized: "공을 뺏고 걷어내는 장면이 늘지만 체력이 빨리 줄고 슈팅이 줄어듭니다.")
        }
    }

    /// 농구에서의 설명.
    var localizedBasketballSummary: String {
        switch self {
        case .balanced: String(localized: "특별한 효과가 없습니다.")
        case .greedy: String(localized: "슛을 더 많이 던집니다. 무리한 슛이 섞여 성공률이 조금 떨어지고, 도움과 수비 가담이 줄어듭니다.")
        case .link: String(localized: "도움 기회가 늘고 슛이 줄어듭니다. 도움 하나가 평점에 더 크게 반영됩니다.")
        case .defensive: String(localized: "스틸, 블록, 리바운드에 더 자주 나서지만 체력이 빨리 줄고 슛이 줄어듭니다.")
        }
    }
}

extension Game {
    /// 기세를 한 줄로. 없으면 nil. Core의 `careerStreakText`와 같은 규칙이다.
    var localizedCareerStreakText: String? {
        if careerStreak >= Balance.careerStreakLength { return String(localized: "\(careerStreak)경기 연속 활약") }
        if careerStreak <= -Balance.careerStreakLength { return String(localized: "\(-careerStreak)경기 연속 부진") }
        return nil
    }

    /// 연속 기록의 이름 (포지션마다 다르다).
    var localizedCareerRunLabel: String {
        guard let me = myPlayer else { return String(localized: "연속 기록") }
        switch me.position.sport {
        case .basketball: return String(localized: "연속 두 자릿수 득점")
        case .duel: return String(localized: "연속 세트 승리")
        case .football: return me.position == .goalkeeper ? String(localized: "연속 무실점") : String(localized: "연속 공격포인트")
        case .baseball: return me.isPitcher ? String(localized: "연속 무자책") : String(localized: "연속 안타")
        }
    }
}

extension CareerRecord {
    /// 명예의 전당 칭호. e스포츠 칭호는 은퇴할 때 글자로 저장되어서 그대로 보여 준다.
    var localizedHonor: String {
        if let duelTitle { return duelTitle }
        return switch bestTier {
        case .pro: awards.isEmpty ? String(localized: "1부 스타") : String(localized: "전설")
        case .semiPro, .amateur: awards.isEmpty ? String(localized: "프로 선수") : String(localized: "프로 스타")
        case .citizenPro, .citizenSemiPro, .citizenAmateur:
            awards.isEmpty ? String(localized: "동네 스타") : String(localized: "시민 리그의 영웅")
        }
    }
}
