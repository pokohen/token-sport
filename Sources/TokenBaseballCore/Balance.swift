import Foundation

/// 조정할 수 있는 수치를 한곳에 모았다. 문서의 💡 수치와, 문서에 "…"로 비어 있던 칸을 채운 값이다.
public enum Balance {
    // MARK: 리그

    public static let teamsPerLeague = 10
    public static let roundsPerSeason = 36
    /// 종목별 리그 크기. 야구는 10팀이 네 번씩 만나 36라운드, 축구는 20팀이 두 번씩 만나 38라운드다.
    public static func teamsPerLeague(_ sport: Sport) -> Int {
        sport == .football ? 20 : teamsPerLeague
    }
    /// 축구: 한 리그 경계에서 플레이오프 없이 바로 승격하는 팀 수. 20팀 리그는 잉글랜드처럼 두 팀(그 아래 네 팀이
    /// 플레이오프로 한 팀 더, 아래 세 팀 강등), 그보다 작은 리그(예전 10팀 저장 파일의 남은 시즌)는 한 팀이다.
    public static func footballAutoPromotions(teams: Int) -> Int { teams >= 20 ? 2 : 1 }

    /// 같은 상대와 홈·원정을 몇 번 도는지. 20팀 리그는 한 번(38라운드), 그보다 작으면 두 번.
    public static func scheduleRepeats(teams: Int) -> Int { teams >= 20 ? 1 : 2 }
    public static func roundsPerSeason(_ sport: Sport) -> Int {
        let teams = teamsPerLeague(sport)
        return (teams - 1) * 2 * scheduleRepeats(teams: teams)
    }
    /// 승강 플레이오프 신청 마감 라운드.
    public static let applicationDeadlineRound = 27
    /// 시즌 중 트레이드 마감 (이 라운드까지 가능).
    public static let tradeDeadlineRound = 24
    public static let friendliesPerOffseason = 5
    /// 신인 드래프트는 친선 몇 경기 뒤에 여는지.
    public static let draftAfterFriendly = 3

    /// 새로 생성되는 선수의 능력 범위.
    public static func abilityRange(_ tier: LeagueTier) -> ClosedRange<Double> {
        switch tier {
        case .citizenAmateur: 15...35
        case .citizenSemiPro: 25...45
        case .citizenPro: 35...55
        case .amateur: 45...65
        case .semiPro: 55...72
        case .pro: 62...90
        }
    }

    /// 잠재력 = 능력 + 0...이 값.
    public static func potentialBonus(_ tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 10
        case .citizenSemiPro: 12
        case .citizenPro: 15
        case .amateur: 20
        case .semiPro: 20
        case .pro: 15
        }
    }

    public static func ageRange(_ tier: LeagueTier) -> ClosedRange<Int> {
        switch tier {
        case .citizenAmateur: 20...45
        case .citizenSemiPro: 20...40
        case .citizenPro: 19...37
        case .amateur: 19...33
        case .semiPro: 19...34
        case .pro: 19...36
        }
    }

    /// 리그별 팀 강도 범위.
    public static func strengthRange(_ tier: LeagueTier) -> ClosedRange<Double> {
        switch tier {
        case .citizenAmateur: 20...40
        case .citizenSemiPro: 30...50
        case .citizenPro: 40...60
        case .amateur: 50...70
        case .semiPro: 60...80
        case .pro: 70...92
        }
    }

    /// 승격에 필요한 인지도 (이 리그에서 위 리그로).
    public static func requiredFame(from tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 100
        case .citizenSemiPro: 300
        case .citizenPro: 700
        case .amateur: 1_500
        case .semiPro: 3_000
        case .pro: 0
        }
    }

    /// 승강 플레이오프 신청비.
    public static func applicationFee(from tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 1_000_000
        case .citizenSemiPro: 5_000_000
        case .citizenPro: 20_000_000
        case .amateur: 80_000_000
        case .semiPro: 300_000_000
        case .pro: 0
        }
    }

    // MARK: 로스터

    public static func rosterLimit(_ tier: LeagueTier, sport: Sport = .baseball) -> Int {
        if sport == .football {
            switch tier {
            case .pro: return 28
            case .semiPro, .amateur: return 24
            default: return 20
            }
        }
        if sport == .basketball {
            switch tier {
            case .pro: return 16
            case .semiPro, .amateur: return 15
            default: return 13
            }
        }
        switch tier {
        case .pro: return 28
        case .semiPro, .amateur: return 22
        default: return 18
        }
    }

    /// 새 팀을 만들 때의 (야수, 선발, 불펜) 수. 불펜 중 한 명은 마무리다.
    public static func rosterShape(_ tier: LeagueTier) -> (batters: Int, starters: Int, relievers: Int) {
        switch tier {
        case .pro: (15, 5, 8)
        case .semiPro, .amateur: (12, 5, 5)
        default: (9, 3, 2)
        }
    }

    /// 축구 CPU 구단의 포지션별 인원.
    public static func footballShape(
        _ tier: LeagueTier
    ) -> (keepers: Int, defenders: Int, midfielders: Int, forwards: Int) {
        switch tier {
        case .pro: (3, 8, 9, 6)
        case .semiPro, .amateur: (3, 7, 7, 5)
        default: (2, 5, 5, 4)
        }
    }

    /// 농구 CPU 구단의 포지션별 인원 (포인트 가드, 슈팅 가드, 스몰 포워드, 파워 포워드, 센터).
    public static func basketballShape(_ tier: LeagueTier) -> [Int] {
        tier.isCitizen ? [2, 2, 2, 2, 2] : [2, 3, 2, 3, 2]
    }
    public static let basketballStarters = 5
    /// 농구: 이 인원 아래로 내려가면 빈자리를 자동으로 채운다.
    public static let basketballMinSquad = 8

    /// 축구: 이 인원 아래로 내려가면 빈자리를 자동으로 채운다.
    public static let footballMinSquad = 14
    public static let footballStarters = 11
    public static let footballMaxSubs = 5

    public static let minBatters = 9
    public static let minPitchers = 5
    /// 선발 투수가 다시 선발로 나오기까지 쉬는 경기 수.
    public static func starterRest(_ tier: LeagueTier) -> Int { tier.isCitizen ? 2 : 4 }
    public static let foreignPlayerLimit = 3

    // MARK: 시설

    public static let maxFacilityLevel = 10
    public static let trainingNames = [
        "동네 공터", "학교 운동장 대여", "실내 연습장", "전용 훈련장", "웨이트장 추가",
        "비디오 분석실", "2군 전용 구장", "재활·회복 센터", "데이터 랩", "첨단 퍼포먼스 센터",
    ]
    public static let trainingMultiplier = [1.0, 1.1, 1.2, 1.35, 1.5, 1.7, 1.9, 2.1, 2.3, 2.5]
    /// 레벨 n → n+1 업그레이드 비용 (index 0 = Lv1 → Lv2).
    public static let trainingCost = [
        10_000_000, 30_000_000, 80_000_000, 200_000_000, 400_000_000,
        800_000_000, 1_500_000_000, 3_000_000_000, 6_000_000_000,
    ]

    public static let stadiumNames = [
        "동네 야구장", "간이 관중석", "구립 야구장", "시립 야구장", "외야석 증축",
        "조명탑 설치", "종합운동장 야구장", "전용 야구장", "신축 야구장", "돔구장",
    ]
    public static let footballTrainingNames = [
        "동네 풋살장", "학교 운동장 대여", "인조잔디 연습장", "전용 훈련장", "웨이트장 추가",
        "비디오 분석실", "2군 전용 구장", "재활·회복 센터", "데이터 랩", "첨단 퍼포먼스 센터",
    ]
    public static let footballStadiumNames = [
        "동네 운동장", "간이 관중석", "구립 축구장", "시립 축구장", "관중석 증축",
        "조명탑 설치", "종합운동장", "전용 축구 경기장", "신축 경기장", "대형 전용 구장",
    ]
    public static func trainingNames(_ sport: Sport) -> [String] {
        sport == .football ? footballTrainingNames : trainingNames
    }
    public static func stadiumNames(_ sport: Sport) -> [String] {
        sport == .football ? footballStadiumNames : stadiumNames
    }

    public static let stadiumCapacity = [100, 500, 2_000, 5_000, 8_000, 12_000, 15_000, 18_000, 22_000, 25_000]
    /// 홈 보정 (0.01 = +1%).
    /// 가장 큰 경기장에서 같은 전력끼리 홈 승률이 54~55%가 되는 수준이다.
    public static let stadiumHomeEdge = [0.005, 0.007, 0.009, 0.011, 0.013, 0.016, 0.019, 0.021, 0.023, 0.025]
    public static let stadiumCost = [
        15_000_000, 50_000_000, 150_000_000, 300_000_000, 600_000_000,
        1_200_000_000, 2_500_000_000, 5_000_000_000, 10_000_000_000,
    ]
    /// 경기장 레벨이 오를 때 받는 인지도 (도달한 레벨 × 이 값).
    public static let stadiumFamePerLevel = 20.0

    public static let maxScoutLevel = 5
    /// 스카우트 시설 Lv0 → Lv1 ... 비용.
    public static let scoutCost = [5_000_000, 20_000_000, 60_000_000, 200_000_000, 500_000_000]

    // MARK: 수입

    public static func ticketPrice(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 500
        case .citizenSemiPro: 800
        case .citizenPro: 1_200
        case .amateur: 2_000
        case .semiPro: 3_500
        case .pro: 6_000
        }
    }

    /// 관중 비율: 리그별 필요 인지도 대비 내 인지도로 정한다.
    public static func attendanceRatio(fame: Double, tier: LeagueTier) -> Double {
        let reference = max(100, requiredFame(from: tier == .pro ? .semiPro : tier))
        return clamp(0.15 + 0.7 * fame / reference, 0.15, 1.0)
    }

    /// 스폰서: 경기마다 인지도 1당 받는 금액.
    public static func sponsorPerFame(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 300
        case .citizenSemiPro: 600
        case .citizenPro: 1_200
        case .amateur: 3_000
        case .semiPro: 8_000
        case .pro: 20_000
        }
    }

    /// 시즌 순위 상금 (1위 기준). 순위가 내려갈수록 줄고 6위부터는 없다.
    public static func prizeMoney(_ tier: LeagueTier, rank: Int) -> Int {
        let top: Int
        switch tier {
        case .citizenAmateur: top = 2_000_000
        case .citizenSemiPro: top = 6_000_000
        case .citizenPro: top = 20_000_000
        case .amateur: top = 80_000_000
        case .semiPro: top = 300_000_000
        case .pro: top = 1_000_000_000
        }
        let share = [1.0, 0.6, 0.4, 0.25, 0.15]
        return rank >= 1 && rank <= share.count ? Int(Double(top) * share[rank - 1]) : 0
    }

    /// 승격 지원금 (올라간 리그 기준).
    public static func promotionGrant(to tier: LeagueTier) -> Int {
        prizeMoney(tier, rank: 1) / 2 + 3_000_000
    }

    /// CPU 구단의 경기당 기본 수입.
    public static func cpuIncomePerMatch(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 300_000
        case .citizenSemiPro: 900_000
        case .citizenPro: 2_500_000
        case .amateur: 8_000_000
        case .semiPro: 25_000_000
        case .pro: 80_000_000
        }
    }

    // MARK: 연봉과 이적료

    /// 능력에 맞는 시즌 연봉 (시장가).
    public static func marketSalary(ability: Double) -> Int {
        let perMatch = 40 * exp(ability * 0.13)
        let season = perMatch * Double(roundsPerSeason)
        return max(10_000, Int(season / 1_000) * 1_000)
    }

    /// 이적료 시장가.
    public static func transferValue(ability: Double, potential: Double, age: Int) -> Int {
        let ageFactor: Double = age <= 24 ? 1.5 : age <= 29 ? 1.2 : age <= 32 ? 0.8 : 0.4
        let upside = 1 + max(0, potential - ability) * 0.03
        return Int(Double(marketSalary(ability: ability)) * 2.5 * ageFactor * upside / 1_000) * 1_000
    }

    public static let raiseBase = 0.03...0.05
    public static let raiseMaxBonus = 0.20

    // MARK: 인지도

    public static let fameWin = 3.0
    public static let fameDraw = 1.0
    /// 3연승부터 승리마다 추가.
    public static let fameWinStreakBonus = 1.0
    /// 5연패부터 패배마다 감소.
    public static let fameLosingStreakPenalty = 2.0
    public static let fameSeasonDecay = 0.10
    public static let fameRelegationDrop = 0.30
    public static let fameAward = 30.0
    public static func famePromotion(to tier: LeagueTier) -> Double { requiredFame(from: tier.lower ?? tier) * 0.3 }
    public static let fameFriendlyUpset = 2.0
    public static let fameFranchiseStar = 200.0

    // MARK: 성장

    /// 틱(경기 한 번)마다의 기본 성장 포인트.
    public static let growthBase = 0.5
    public static func ageGrowthFactor(_ age: Int) -> Double {
        switch age {
        case ...22: 1.5
        case 23...26: 1.0
        case 27...30: 0.4
        default: 0
        }
    }
    public static let playFactorStarter = 1.2
    public static let playFactorSub = 1.0
    public static let playFactorBench = 0.6
    public static let friendlyGrowthFactor = 0.5
    /// 은퇴를 생각하기 시작하는 나이.
    public static func retirementAge(_ tier: LeagueTier) -> Int { tier.isCitizen ? 42 : 34 }
    public static let declineStartAge = 34

    /// 포지션까지 본 성장 계수. 축구 필드 선수는 전성기가 조금 이르고, 골키퍼는 늦게까지 큰다.
    public static func ageGrowthFactor(_ age: Int, position: Position) -> Double {
        if position.sport == .basketball {
            // 농구: 20대 중반까지 크고 서른이면 멈춘다.
            switch age {
            case ...22: return 1.5
            case 23...26: return 1.0
            case 27...29: return 0.4
            default: return 0
            }
        }
        guard position.sport == .football else { return ageGrowthFactor(age) }
        if position == .goalkeeper {
            switch age {
            case ...23: return 1.5
            case 24...28: return 1.0
            case 29...31: return 0.4
            default: return 0
            }
        }
        switch age {
        case ...21: return 1.5
        case 22...25: return 1.0
        case 26...28: return 0.4
        default: return 0
        }
    }

    /// 능력치가 본격적으로 떨어지기 시작하는 나이. 축구 골키퍼는 늦다.
    public static func declineStartAge(_ position: Position) -> Int {
        switch position.sport {
        case .football: position == .goalkeeper ? 35 : 33
        case .basketball: 33
        case .baseball: declineStartAge
        }
    }

    /// 그보다 앞서, 몸으로 하는 능력치만 조금씩 내려가기 시작하는 나이.
    public static func earlyDeclineAge(_ position: Position) -> Int {
        switch position.sport {
        case .football: position == .goalkeeper ? 33 : 30
        case .basketball: 30
        case .baseball: 31
        }
    }

    /// 은퇴를 생각하기 시작하는 나이. 골키퍼는 3년 늦다.
    public static func retirementAge(_ tier: LeagueTier, position: Position) -> Int {
        retirementAge(tier) + (position == .goalkeeper && !tier.isCitizen ? 3 : 0)
    }

    /// 축구 출장 정지: 퇴장이면 쉬는 리그 경기 수, 그리고 시즌 경고 몇 장마다 한 경기를 쉬는지.
    public static let footballRedCardBan = 1
    public static let footballYellowsPerBan = 5

    /// 축구 이적 기간: 여름(오프시즌과 개막 직후 세 라운드)과 겨울(시즌 중반 네 라운드).
    public static let footballSummerWindowRounds = 3
    public static let footballWinterWindow = 16...19

    /// 축구: 승격에 필요한 구장 등급(경기장 레벨). 잉글랜드 리그의 구장 등급 심사를 본떴다.
    public static func promotionStadiumLevel(from tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 2
        case .citizenSemiPro: 3
        case .citizenPro: 4
        case .amateur: 5
        case .semiPro: 6
        case .pro: 0
        }
    }

    // MARK: 재정 위기

    public static let bankruptcyGraceMatches = 5
    public static let warningMatches = 5

    // MARK: 경기 기회

    public static let matchChargeInterval: TimeInterval = 60 * 60
    public static let maxMatchCharges = 3
    /// 토큰으로 경기 기회를 하나 사는 값. 연달아 사면 두 배씩 오른다 (최대 `extraMatchMaxDoublings`번).
    public static let extraMatchCost = 3_000_000
    public static let extraMatchMaxDoublings = 6
    /// 진행 중인 경기를 기다리지 않고 끝까지 치르는 값 (토큰). 결과는 지켜봤을 때와 같다.
    public static let skipMatchCost = 1_000_000

    // MARK: 영입

    public static func tryoutFee(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 200_000
        case .citizenSemiPro: 600_000
        case .citizenPro: 2_000_000
        case .amateur: 6_000_000
        case .semiPro: 20_000_000
        case .pro: 60_000_000
        }
    }
}
