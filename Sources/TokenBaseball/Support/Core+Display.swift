import TokenBaseballCore

// Core가 만드는 이름을 화면에서 번역해 보여 준다.
// Core의 한국어(rawValue, label)는 저장 파일과 지문 테스트에 들어가서 그대로 둔다. 화면은 여기 이름만 쓴다.
// 한국어 문구는 Core와 글자 하나까지 같다 (한국어 화면이 바뀌지 않게).

extension Sport {
    var localizedLabel: String {
        switch self {
        case .baseball: String(localized: "야구")
        case .football: String(localized: "축구")
        case .basketball: String(localized: "농구")
        case .duel: String(localized: "e스포츠")
        }
    }
}

extension SaveSlot {
    var localizedLabel: String {
        switch self {
        case .baseball: String(localized: "야구 구단")
        case .football: String(localized: "축구 구단")
        case .baseballPlayer: String(localized: "야구 선수")
        case .footballPlayer: String(localized: "축구 선수")
        case .basketballPlayer: String(localized: "농구 선수")
        case .duelPlayer: String(localized: "e스포츠 선수")
        }
    }
}

extension MatchKind {
    var localizedLabel: String {
        switch self {
        case .regular: String(localized: "정규시즌")
        case .playoff: String(localized: "승강 플레이오프")
        case .friendly: String(localized: "친선 경기")
        case .cup: String(localized: "컵대회")
        }
    }
}

extension RubberBand {
    var localizedName: String {
        switch self {
        case .off: String(localized: "끄기")
        case .weak: String(localized: "약하게")
        case .normal: String(localized: "보통")
        case .strong: String(localized: "강하게")
        }
    }
}

extension MenuBarDisplay {
    var localizedName: String {
        switch self {
        case .funds: String(localized: "구단 자금")
        case .today: String(localized: "오늘 사용량")
        case .nextMatch: String(localized: "다음 경기")
        }
    }
}

extension LeagueTier {
    var localizedName: String {
        switch self {
        case .pro: String(localized: "프로")
        case .semiPro: String(localized: "세미프로")
        case .amateur: String(localized: "아마추어")
        case .citizenPro: String(localized: "시민 프로")
        case .citizenSemiPro: String(localized: "시민 세미프로")
        case .citizenAmateur: String(localized: "시민 아마추어")
        }
    }

    /// "6부 시민 아마추어".
    var localizedDisplayName: String { String(localized: "\(rawValue)부 \(localizedName)") }

    /// 종목에 맞는 리그 이름. e스포츠만 이름이 다르다.
    func localizedName(for sport: Sport) -> String {
        switch sport {
        case .baseball, .football, .basketball: localizedName
        case .duel:
            switch self {
            case .pro: String(localized: "프로 리그")
            case .semiPro: String(localized: "챌린저 리그")
            case .amateur: String(localized: "아카데미 리그")
            case .citizenPro: String(localized: "대학·클럽 리그")
            case .citizenSemiPro: String(localized: "지역 아마추어 리그")
            case .citizenAmateur: String(localized: "PC방 리그")
            }
        }
    }

    /// "6부 PC방 리그".
    func localizedDisplayName(for sport: Sport) -> String { String(localized: "\(rawValue)부 \(localizedName(for: sport))") }
}

extension LastResult {
    /// "승 3:2", "패 1:2 승부차기".
    var localizedLabel: String {
        if let shootoutWon {
            return shootoutWon
                ? String(localized: "승 \(myRuns):\(theirRuns) 승부차기") : String(localized: "패 \(myRuns):\(theirRuns) 승부차기")
        }
        if myRuns > theirRuns { return String(localized: "승 \(myRuns):\(theirRuns)") }
        if myRuns < theirRuns { return String(localized: "패 \(myRuns):\(theirRuns)") }
        return String(localized: "무 \(myRuns):\(theirRuns)")
    }
}

extension Position {
    var localizedLabel: String {
        switch self {
        case .starter: String(localized: "선발")
        case .reliever: String(localized: "불펜")
        case .closer: String(localized: "마무리")
        case .catcher: String(localized: "포수")
        case .first: String(localized: "1루수")
        case .second: String(localized: "2루수")
        case .third: String(localized: "3루수")
        case .shortstop: String(localized: "유격수")
        case .left: String(localized: "좌익수")
        case .center: String(localized: "중견수")
        case .right: String(localized: "우익수")
        case .designated: String(localized: "지명타자")
        case .goalkeeper: String(localized: "골키퍼")
        case .defender: String(localized: "수비수")
        case .midfielder: String(localized: "미드필더")
        case .forward: String(localized: "공격수")
        case .pointGuard: String(localized: "포인트 가드")
        case .shootingGuard: String(localized: "슈팅 가드")
        case .smallForward: String(localized: "스몰 포워드")
        case .powerForward: String(localized: "파워 포워드")
        case .center5: String(localized: "센터")
        case .human: String(localized: "휴먼")
        case .alien: String(localized: "에일리언")
        case .protector: String(localized: "프로텍터")
        }
    }
}

extension Attributes.Key {
    // 야구의 수비(.fielding)와 축구·농구의 수비(.tackling)는 영어로 다르다. 야구 쪽은 Attribute 표에 둔다.
    var localizedLabel: String {
        switch self {
        case .contact: String(localized: "컨택")
        case .power: String(localized: "파워")
        case .eye: String(localized: "선구안")
        case .speed: String(localized: "주력")
        case .fielding: String(localized: "수비", table: "Attribute")
        case .arm: String(localized: "어깨")
        case .stuff: String(localized: "구위")
        case .control: String(localized: "제구")
        case .breaking: String(localized: "변화구")
        case .stamina: String(localized: "체력")
        case .shooting: String(localized: "슈팅")
        case .passing: String(localized: "패스")
        case .dribbling: String(localized: "드리블")
        case .tackling: String(localized: "수비")
        case .physical: String(localized: "피지컬")
        case .keeping: String(localized: "골키핑")
        // 경기 기록의 "3점슛", "리바운드"(개수)와 뜻이 달라서 따로 둔다.
        case .three: String(localized: "3점슛", table: "Attribute")
        case .rebounding: String(localized: "리바운드", table: "Attribute")
        case .macro: String(localized: "운영")
        case .strategy: String(localized: "전략")
        case .judgment: String(localized: "판단")
        case .mental: String(localized: "멘탈")
        }
    }

    /// 종목에 맞는 이름. 야구는 주력, 축구와 농구는 스피드다. 농구의 슈팅은 슛이다.
    func localizedLabel(for sport: Sport) -> String {
        switch sport {
        case .baseball: localizedLabel
        case .football: self == .speed ? String(localized: "스피드") : localizedLabel
        case .basketball: self == .speed ? String(localized: "스피드") : self == .shooting ? String(localized: "슛") : localizedLabel
        case .duel: self == .control ? String(localized: "컨트롤") : localizedLabel
        }
    }
}

extension Trait {
    var localizedName: String {
        switch self {
        case .clutch: String(localized: "찬스에 강함")
        case .slowStarter: String(localized: "첫 타석 약함")
        case .leftyKiller: String(localized: "왼손 투수 킬러")
        case .ironGlove: String(localized: "철벽 수비")
        case .coolHead: String(localized: "위기에 강함")
        case .ironLungs: String(localized: "강철 체력")
        case .setPiece: String(localized: "프리킥 장인")
        }
    }
}

extension TeamStyle {
    func localizedLabel(_ sport: Sport) -> String {
        switch self {
        case .youth: String(localized: "유망주 육성형")
        case .veteran: String(localized: "베테랑 선호형")
        case .pitching: sport.groupsByPosition ? String(localized: "수비 중시형") : String(localized: "투수력 중시형")
        case .balanced: String(localized: "균형형")
        }
    }
}
