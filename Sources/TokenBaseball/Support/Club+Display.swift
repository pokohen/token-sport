import TokenBaseballCore

// 구단 경영 화면의 이름: 홍보, 시설, 재정 항목, 영입, 전술.

extension Promotion {
    func localizedLabel(_ sport: Sport) -> String {
        switch self {
        case .flyer: String(localized: "전단지")
        case .newspaper: String(localized: "지역 신문 광고")
        case .sns: String(localized: "SNS 캠페인")
        case .festival: String(localized: "지역 축제 참가")
        case .youthClinic:
            switch sport {
            case .football: String(localized: "유소년 축구 교실")
            case .duel: String(localized: "유소년 게임 교실")
            case .baseball, .basketball: String(localized: "유소년 야구 교실")
            }
        case .tv: String(localized: "TV 광고")
        }
    }

    /// 덧붙이는 설명. 없으면 빈 글자.
    var localizedNote: String {
        switch self {
        case .festival: String(localized: "시즌 중 1회")
        case .youthClinic: String(localized: "다음 입단 테스트에 유망주 후보가 늘어남")
        case .tv: String(localized: "3부 이상")
        case .flyer, .newspaper, .sns: ""
        }
    }
}

extension Facility {
    var localizedName: String {
        switch self {
        case .training: String(localized: "훈련소")
        case .stadium: String(localized: "경기장")
        case .scout: String(localized: "스카우트")
        }
    }

    /// 레벨마다의 훈련소 이름 (index 0 = Lv1). `Balance.trainingNames`와 같은 순서다.
    static func localizedTrainingNames(_ sport: Sport) -> [String] {
        switch sport {
        case .football:
            [
                String(localized: "동네 풋살장"), String(localized: "학교 운동장 대여"), String(localized: "인조잔디 연습장"),
                String(localized: "전용 훈련장"), String(localized: "웨이트장 추가"), String(localized: "비디오 분석실"),
                String(localized: "2군 전용 구장"), String(localized: "재활·회복 센터"), String(localized: "데이터 랩"),
                String(localized: "첨단 퍼포먼스 센터"),
            ]
        case .baseball, .basketball, .duel:
            [
                String(localized: "동네 공터"), String(localized: "학교 운동장 대여"), String(localized: "실내 연습장"),
                String(localized: "전용 훈련장"), String(localized: "웨이트장 추가"), String(localized: "비디오 분석실"),
                String(localized: "2군 전용 구장"), String(localized: "재활·회복 센터"), String(localized: "데이터 랩"),
                String(localized: "첨단 퍼포먼스 센터"),
            ]
        }
    }

    /// 레벨마다의 경기장 이름 (index 0 = Lv1). `Balance.stadiumNames`와 같은 순서다.
    static func localizedStadiumNames(_ sport: Sport) -> [String] {
        switch sport {
        case .football:
            [
                String(localized: "동네 운동장"), String(localized: "간이 관중석"), String(localized: "구립 축구장"),
                String(localized: "시립 축구장"), String(localized: "관중석 증축"), String(localized: "조명탑 설치"),
                String(localized: "종합운동장"), String(localized: "전용 축구 경기장"), String(localized: "신축 경기장"),
                String(localized: "대형 전용 구장"),
            ]
        case .baseball, .basketball, .duel:
            [
                String(localized: "동네 야구장"), String(localized: "간이 관중석"), String(localized: "구립 야구장"),
                String(localized: "시립 야구장"), String(localized: "외야석 증축"), String(localized: "조명탑 설치"),
                String(localized: "종합운동장 야구장"), String(localized: "전용 야구장"), String(localized: "신축 야구장"),
                String(localized: "돔구장"),
            ]
        }
    }
}

extension FundsLedger.Category {
    // rawValue는 저장 파일의 열쇠다. 화면에만 이 이름을 쓴다.
    var localizedName: String {
        switch self {
        case .tokens: String(localized: "토큰")
        case .gate: String(localized: "관중 수입")
        case .sponsor: String(localized: "스폰서")
        case .prize: String(localized: "상금·지원금")
        case .sales: String(localized: "선수 판매")
        case .salary: String(localized: "선수 연봉")
        case .facility: String(localized: "시설")
        case .promotion: String(localized: "홍보")
        case .recruit: String(localized: "선수 영입")
        case .fee: String(localized: "승강 신청비")
        case .training: String(localized: "훈련")
        case .extraMatch: String(localized: "추가 경기")
        case .skipMatch: String(localized: "결과 바로 보기")
        }
    }
}

extension Proposal.Kind {
    var localizedName: String {
        switch self {
        case .freeAgent: String(localized: "FA 영입")
        case .renewal: String(localized: "재계약")
        case .transfer: String(localized: "이적 제안")
        }
    }
}

extension Candidate.Source {
    var localizedName: String {
        switch self {
        case .tryout: String(localized: "입단 테스트")
        // 시설 "스카우트"와 뜻이 달라서(스카우트가 찾은 후보) Market 표에 둔다.
        case .scout: String(localized: "스카우트", table: "Market")
        case .draft: String(localized: "신인 드래프트")
        }
    }
}

extension ScoutRegion {
    var localizedName: String {
        switch self {
        case .local: String(localized: "연고지")
        case .national: String(localized: "전국")
        case .overseas: String(localized: "해외")
        }
    }
}

extension Tactic {
    var localizedName: String {
        switch self {
        case .attacking: String(localized: "공격적")
        // 플레이 스타일 "균형"과 따로 옮길 수 있게 Tactic 표에 둔다.
        case .balanced: String(localized: "균형", table: "Tactic")
        case .defensive: String(localized: "수비적")
        }
    }
}

extension Formation {
    var localizedSummary: String {
        switch self {
        case .f442: String(localized: "기본형. 강한 곳도 약한 곳도 없습니다.")
        case .f433: String(localized: "공격수 3명. 상대 진영에서 기회를 더 만들지만 중원 싸움에서 밀립니다.")
        case .f4231: String(localized: "미드필더 5명에 원톱. 중원을 잡지만 상대 진영에서 기회가 줄어듭니다.")
        case .f41212: String(localized: "다이아몬드 중원. 중원을 장악하지만 측면이 비어 우리 진영 수비가 약해집니다.")
        case .f352: String(localized: "수비수 3명에 미드필더 5명. 중원이 가장 강하지만 우리 진영 수비가 가장 약합니다.")
        case .f343: String(localized: "수비수 3명에 공격수 3명. 기회를 가장 많이 만들지만 뒤가 열립니다.")
        case .f532: String(localized: "수비수 5명. 우리 진영 수비가 단단하지만 중원 싸움에서 밀립니다.")
        }
    }
}
