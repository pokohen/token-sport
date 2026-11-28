import TokenBaseballCore

// e스포츠 화면의 이름: 대회, 종족, 스타일, 빌드, 맵 소개, 칭호, 종족별 전적.

extension DuelTournament {
    var localizedBaseName: String {
        switch self {
        case .pcBang: String(localized: "동네 PC방 대회")
        case .city: String(localized: "시장배 아마추어 대회")
        case .national: String(localized: "전국 e스포츠 선수권")
        case .korea: String(localized: "코리아 그랜드 리그")
        case .asia: String(localized: "아시아 마스터즈")
        case .world: String(localized: "월드 그랜드 파이널")
        }
    }
}

extension DuelRace {
    var localizedLabel: String {
        switch self {
        case .human: String(localized: "휴먼")
        case .alien: String(localized: "에일리언")
        case .protector: String(localized: "프로텍터")
        }
    }
}

extension DuelStyle {
    // "균형"은 축구·농구 플레이 스타일과 같은 뜻이라 같은 문구를 쓴다.
    var localizedLabel: String {
        switch self {
        case .balanced: String(localized: "균형")
        case .rush: String(localized: "러시형")
        case .macro: String(localized: "운영형")
        case .gambit: String(localized: "전략형")
        }
    }
}

extension DuelBuild {
    var localizedLabel: String {
        switch self {
        case .aggressive: String(localized: "초반 공격")
        case .standard: String(localized: "안정")
        case .fastExpand: String(localized: "빠른 확장")
        }
    }
}

extension DuelMap {
    /// "본진이 먼 넓은 맵, 휴먼이 조금 유리한 맵입니다" 같은 한 줄 소개.
    /// 종족 이름 뒤에 조사를 따로 붙이지 않으려고 모양과 종족마다 문장을 통째로 둔다 (한국어는 Core와 같다).
    var localizedNote: String {
        switch (shape, favors) {
        case (.narrow, nil): String(localized: "본진이 가까운 좁은 맵입니다")
        case (.narrow, .human): String(localized: "본진이 가까운 좁은 맵, 휴먼이 조금 유리한 맵입니다")
        case (.narrow, .alien): String(localized: "본진이 가까운 좁은 맵, 에일리언이 조금 유리한 맵입니다")
        case (.narrow, .protector): String(localized: "본진이 가까운 좁은 맵, 프로텍터이 조금 유리한 맵입니다")
        case (.wide, nil): String(localized: "본진이 먼 넓은 맵입니다")
        case (.wide, .human): String(localized: "본진이 먼 넓은 맵, 휴먼이 조금 유리한 맵입니다")
        case (.wide, .alien): String(localized: "본진이 먼 넓은 맵, 에일리언이 조금 유리한 맵입니다")
        case (.wide, .protector): String(localized: "본진이 먼 넓은 맵, 프로텍터이 조금 유리한 맵입니다")
        case (.open, nil): String(localized: "확장할 자리가 많은 맵입니다")
        case (.open, .human): String(localized: "확장할 자리가 많은 맵, 휴먼이 조금 유리한 맵입니다")
        case (.open, .alien): String(localized: "확장할 자리가 많은 맵, 에일리언이 조금 유리한 맵입니다")
        case (.open, .protector): String(localized: "확장할 자리가 많은 맵, 프로텍터이 조금 유리한 맵입니다")
        }
    }
}

extension DuelLine {
    /// 그 종족을 상대로 한 전적: "12승 5패". Core의 `versusText`에서 "대 종족"을 뺀 것이다.
    func localizedVersusRecord(_ race: DuelRace) -> String {
        let record = versus[race.rawValue] ?? [0, 0]
        // Core는 자리 구분 없이 쓴다. 정수를 그대로 끼우면 1,000처럼 쉼표가 붙어서 글자로 먼저 바꾼다.
        return String(localized: "\(String(record[0]))승 \(String(record[1]))패")
    }
}

extension Game {
    /// 칭호. Core의 `duelTitle`과 같은 규칙이다 (우승한 가장 큰 대회, 그 대회 이상의 우승 횟수, 팬 수).
    /// 도시 이름은 선수의 출신(저장된 글자)에서 가져와 그대로 쓴다.
    var localizedDuelTitle: String? {
        guard let career, let fans = career.fans else { return nil }
        let wins = career.duelWins ?? []
        guard let best = DuelTournament.allCases.sorted().first(where: { wins.count >= $0.rawValue && wins[$0.rawValue - 1] > 0 })
        else {
            return fans >= 100_000 ? String(localized: "무관의 스타") : nil
        }
        let count = DuelTournament.allCases.filter { $0 <= best }.reduce(0) { $0 + wins[$1.rawValue - 1] }
        let city = (players[career.playerID]?.origin.split(separator: " ").first).map(String.init) ?? String(localized: "고향")
        let title: String = switch best {
        case .pcBang: count >= 3 ? String(localized: "PC방의 전설") : String(localized: "동네 고수")
        case .city: count >= 3 ? String(localized: "\(city)의 자존심") : String(localized: "\(city) 최강")
        case .national: count >= 3 ? String(localized: "전국 최강") : String(localized: "전국구")
        case .korea: count >= 5 ? String(localized: "황제") : count >= 3 ? String(localized: "왕") : String(localized: "챔피언")
        case .asia: count >= 3 ? String(localized: "아시아의 지배자") : String(localized: "아시아의 별")
        case .world:
            count >= 5 ? String(localized: "살아 있는 전설") : count >= 3 ? String(localized: "세계의 왕") : String(localized: "세계 챔피언")
        }
        if fans >= 10_000_000 { return String(localized: "모두의 \(title)") }
        if fans >= 1_000_000 { return String(localized: "국민 \(title)") }
        if fans * 10 < best.requiredFans { return String(localized: "숨은 \(title)") }
        return title
    }
}
