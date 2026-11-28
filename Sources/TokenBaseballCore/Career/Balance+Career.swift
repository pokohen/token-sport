import Foundation

/// 선수 모드에서 조정할 수 있는 수치.
extension Balance {
    // 컵대회

    /// 1라운드를 쉬는 구단 수 (1부에서 강한 순서로): 1라운드가 끝나면 32팀이나 64팀이 남게 맞춘다 (60팀이면 4, 120팀이면 8).
    public static func cupByes(entrants: Int) -> Int {
        var bracket = 1
        while bracket * 2 <= entrants { bracket *= 2 }
        return bracket == entrants ? 0 : bracket * 2 - entrants
    }
    /// 컵 라운드가 열리는 때: 리그를 이만큼 치른 뒤.
    /// 여섯 라운드 대회(60팀: 1라운드, 32강, 16강, 8강, 준결승, 결승)와 일곱 라운드 대회(120팀: 64강이 더 있다).
    public static func cupAfterRounds(total: Int) -> [Int] {
        total >= 7 ? [3, 8, 13, 18, 23, 29, 35] : [4, 10, 16, 22, 28, 33]
    }
    /// 컵 경기에서 이겨 올라갈 때 오르는 명성, 윗 리그 구단을 잡으면 리그 차이 하나마다 더 오르는 명성.
    public static let cupWinFame = 1.0
    public static let cupUpsetFame = 2.0
    public static let cupChampionFame = 12.0
    public static let cupRunnerUpFame = 5.0
    public static let cupChampionTrust = 5.0

    // 컨디션, 기세, 라이벌, 실전 경험

    /// 평점이 이 값 이상이면 "활약", 이 값 이하면 "부진"으로 센다.
    public static let careerStreakGood = 7.0
    public static let careerStreakBad = 5.5
    /// 이 경기 수만큼 이어지면 기세(또는 슬럼프)가 붙는다.
    public static let careerStreakLength = 3
    /// 기세가 능력치에 주는 변화 (0.02 = 2%).
    public static let careerMomentum = 0.02
    /// 기세가 붙어 있을 때 경기로 얻는 명성의 배수.
    public static let careerMomentumFame = 1.25
    /// 라이벌은 내 능력보다 이만큼 높은 선수에 가장 가까운 선수로 고른다.
    public static let careerRivalEdge = 2.0
    /// 라이벌은 나보다 이 나이 차이 안쪽의 또래를 먼저 고른다.
    public static let careerRivalAgeGap = 6
    /// 새 시즌에 내가 이만큼 넘게 앞서 있으면 라이벌을 바꾼다.
    public static let careerRivalOutgrown = 5.0
    /// 라이벌과의 맞대결에서 이기면 오르는 명성.
    public static let careerRivalFame = 1.0
    /// 토큰으로 치른 경기에서 얻는 능력: 기본 + (평점 − 6) × 평점당, 최대까지.
    public static let careerExtraMatchBase = 0.02
    public static let careerExtraMatchPerRating = 0.03
    public static let careerExtraMatchMax = 0.1

    // 스카우트

    /// 스카우트가 오는 구단은 내 리그보다 이만큼 위까지다 (같은 리그 포함). 한 번에 두 리그까지만 뛰어오를 수 있다.
    public static let careerScoutTierReach = 2
    /// 한 번에 나를 지켜보는 구단 수.
    public static let careerScoutMax = 3
    /// 이 관심도를 넘은 구단이 이적 기간에 제안한다. 이적을 요청했으면, 계약이 끝났으면 문턱이 낮아진다.
    public static let careerScoutOfferInterest = 70.0
    public static let careerScoutOfferInterestRequested = 50.0
    public static let careerScoutOfferInterestExpired = 35.0
    /// 관심도는 (평점 − 기준) × 이 값만큼 움직인다. 기준은 명성의 기준(야구 6.5, 축구·농구 6.3)보다 이만큼 낮다.
    public static let careerScoutPerRating = 8.0
    /// 선발 투수는 나오는 경기가 적어서 한 경기가 이만큼 크게 반영된다 (명성과 같다).
    public static let careerScoutStarterPitcher = 3.0
    public static let careerScoutBaselineSlack = 0.3
    /// 그 구단에 가면 주전(또는 주전 경쟁)일 때 경기마다 더 쌓이는 관심도.
    public static let careerScoutFitStarter = 3.5
    public static let careerScoutFitRotation = 1.2
    /// 경기마다 새 스카우트가 지켜보기 시작할 기본 확률.
    public static let careerScoutArrival = 0.12
    /// 스카우트가 다음 경기를 직접 보러 올 확률과, 그 경기에서 관심도가 움직이는 배수.
    public static let careerScoutVisitChance = 0.3
    public static let careerScoutVisitMultiplier = 2.0
    /// 이적을 요청하면 모든 스카우트의 관심도가 이만큼 오른다.
    public static let careerScoutRequestBoost = 10.0
    /// 새 시즌에 남는 관심도의 비율.
    public static let careerScoutSeasonKeep = 0.85

    public static let careerStartAge = 16
    /// 내 선수의 타고난 재능: 시작 능력과 잠재력(성장 한계)이 선수마다 이 범위에서 다르게 정해진다.
    /// 잠재력의 숫자는 숨겨져 있고, 재능 등급으로만 알려 준다.
    public static let careerStartAbility = 15.0...30.0
    public static let careerPotential = 68.0...95.0
    /// 선수를 만들 때 직접 나눠 넣는 시작 포인트의 수와, 포인트 하나에 오르는 능력치.
    public static let careerStartPoints = 5
    public static let careerStartPointValue = 3.0
    /// 능력치 하나에 넣을 수 있는 시작 포인트. 비중이 큰 능력치 하나(골키퍼의 골키핑 등)에 몰아넣어
    /// 포지션마다 시작 능력이 크게 벌어지는 것을 막는다 (다섯 개를 가장 좋게 넣으면 능력 +3.5 ~ +5.4).
    public static let careerStartPointsPerStat = 2
    public static let careerStartTrust = 40.0
    /// 경기와 경기 사이에 할 수 있는 훈련 횟수.
    public static let careerSessionsPerMatch = 5
    /// 이 나이부터는 훈련으로 능력치를 올릴 수 없다.
    public static let careerTrainingAgeLimit = 31
    /// 포지션별 훈련 한도 나이: 성장이 멈추는 나이와 같다.
    public static func careerTrainingAgeLimit(_ position: Position) -> Int {
        switch position.sport {
        case .football: position == .goalkeeper ? 32 : 29
        case .basketball: 30
        case .baseball: careerTrainingAgeLimit
        // e스포츠는 멈추지 않고 나이에 따라 효과가 줄어든다 (`duelAgeFactor`). 은퇴가 35세다.
        case .duel: 36
        }
    }
    /// 농구: 선발이 아닐 때 벤치에서 나와 뛰는 시간(분, 40분 경기). 감독 신뢰가 높을수록 길다 (신뢰 0이면 8분, 40이면 15분, 90 이상이면 24분).
    public static func careerBenchMinutes(trust: Double) -> Int {
        Int(clamp(8 + trust * 0.18, 8, 24))
    }
    /// 농구 평점의 포지션별 기준 보정. 시뮬레이션으로 맞춘다.
    public static func careerBasketballBaseline(_ position: Position) -> Double {
        switch position {
        case .pointGuard: -0.3
        case .shootingGuard: -0.3
        case .smallForward: -0.25
        case .powerForward: -0.45
        default: -0.5
        }
    }
    public static func careerForcedRetirementAge(_ position: Position) -> Int {
        // e스포츠는 35세 시즌을 마치면 은퇴한다 (나이는 오프시즌이 시작될 때 먹는다).
        if position.sport == .duel { return duelRetirementAge + 1 }
        return careerForcedRetirementAge + (position == .goalkeeper ? 3 : 0)
    }
    // MARK: e스포츠 1:1 대전

    /// 세트 평점의 기준 이동: 이기면 +, 지면 −. 나머지는 병력·일꾼 교환, 빠른 완승, 역전, 상대 실력으로 정한다.
    public static let careerDuelWinShift = 0.9
    public static let careerDuelLossShift = -0.7
    /// 내 선수가 출전 순서에 들지 못해도 이 경기 수가 지나면 한 세트를 받는다.
    public static let careerDuelGuaranteedEvery = 4
    /// 팀에서 순위가 낮아도 지난 시즌 평점이 이만큼이면 재계약을 제안받는다.
    public static let careerDuelRenewalRating = 6.0
    /// 세트를 이길 때마다 리그만큼 느는 팬 (6부 → 1부).
    public static func duelFanBase(_ tier: LeagueTier) -> Int {
        switch tier {
        case .citizenAmateur: 35
        case .citizenSemiPro: 45
        case .citizenPro: 100
        case .amateur: 250
        case .semiPro: 700
        case .pro: 1_800
        }
    }
    /// 세트를 이길 때마다 지금 팬의 이만큼이 더 는다 (팬이 팬을 부른다).
    public static let duelFanShare = 0.012
    /// 팬이 이 수에 가까울수록 덜 는다 (나라 안의 e스포츠 팬이 그쯤이다). 1,000만 명에서 느는 양이 3분의 2로 준다.
    public static let duelFanCeiling = 30_000_000
    /// 팬이 이미 많을수록 줄어드는 배수 (0.1 ~ 1).
    public static func duelFanRoom(_ fans: Int) -> Double {
        max(0.1, 1 - Double(fans) / Double(duelFanCeiling))
    }
    /// 세 경기 넘게 지면 경기마다 팬이 이만큼 준다.
    public static let duelFanSlumpLoss = 0.01
    /// 오프시즌마다 줄어드는 팬 몫.
    public static let duelFanSeasonDecay = 0.05
    /// 팬 수로 낸 명성 (0~100): 100명 ≈ 29, 1만 명 ≈ 57, 100만 명 ≈ 86, 1,000만 명 = 100.
    public static func duelFame(fans: Int) -> Double {
        min(100, log10(Double(max(0, fans)) + 1) / 7 * 100)
    }

    /// 스스로 은퇴하려면 끝까지 치른 시즌이 이만큼 있어야 한다.
    public static let careerRetireMinSeasons = 1
    public static let careerForcedRetirementAge = 38
    /// 잠재력까지 남은 여유가 이 값 이하면 훈련 비용이 두 배가 된다.
    public static let careerNearPotentialRoom = 10.0
    /// 감독 신뢰가 이 값 이상이어야 구단이 재계약을 제안한다.
    public static let careerRenewalTrust = 30.0
    public static let careerFameAward = 8.0
    /// 한계 돌파 훈련: 잠재력을 +1 올리는 데 드는 훈련 포인트.
    public static let careerBreakthroughCost = 15_000_000
    /// 구단을 옮긴 뒤 이 경기 수가 지나야 다른 구단의 제안이 다시 온다.
    public static let careerOfferCooldown = 10
    /// 축구 평점의 포지션별 기준 보정. 시뮬레이션으로 맞춘다.
    public static func careerFootballBaseline(_ position: Position) -> Double {
        switch position {
        case .goalkeeper: 0.45
        case .defender: 0.0
        case .midfielder: -0.1
        default: 0.2
        }
    }
    /// 축구 골키퍼 평점: 실력이 비슷한 골키퍼를 상대로 유효 슈팅이 골이 되는 비율 (경기 엔진의 0.36).
    public static let careerKeeperShotGoalRate = 0.36
    /// 축구 골키퍼 평점: 막아 낸 골 하나의 값.
    public static let careerKeeperPreventedWeight = 1.2
    /// 축구: 주전이 아닌 골키퍼는 이 경기 수마다 한 번 선발로 나온다.
    public static let careerKeeperRotation = 4
    /// 축구: 선발이 아닐 때 교체로 들어가는 시간(분). 감독 신뢰가 높을수록 일찍 들어간다 (신뢰 20이면 80분, 60이면 60분).
    public static func careerSubMinute(trust: Double) -> Int {
        Int(clamp(90 - trust * 0.5, 50, 85))
    }
    /// 훈련하지 않아도 저절로 크는 정도 (다른 선수의 성장에 곱하는 값).
    public static let careerNaturalGrowth = 0.15
    /// 훈련 한 번에 오르는 능력(CA).
    /// 가운데 리그(4부)의 값이다. 리그마다의 값은 `careerTrainingStep(_:)`.
    public static let careerTrainingStep = 0.035
    /// 리그별 훈련 효과: 윗 리그일수록 훈련 한 번에 능력이 더 많이 오른다 (6부 0.025 → 1부 0.05).
    /// 시설과 코치가 좋아지는 만큼이다. 아랫 리그에서는 아무리 포인트가 많아도 천천히 큰다.
    ///
    /// 한 시즌에 훈련을 220번쯤 할 수 있다 (경기 44개 × 다섯 번). 그래서 훈련을 하나도 빼먹지 않으면
    /// 한 시즌에 6부 +5.5, 3부 +9, 1부 +11이 오른다. 경기만 뛰어 저절로 크는 양(시즌에 4쯤)의 두세 배다.
    public static func careerTrainingStep(_ tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 0.025
        case .citizenSemiPro: 0.03
        case .citizenPro: careerTrainingStep
        case .amateur: 0.04
        case .semiPro: 0.045
        case .pro: 0.05
        }
    }
    /// 리그별 훈련 비용 배수: 윗 리그일수록 훈련 한 번이 비싸다 (6부 0.5배 → 1부 1.4배).
    public static func careerTrainingCostFactor(_ tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 0.5
        case .citizenSemiPro: 0.65
        case .citizenPro: 0.8
        case .amateur: 1.0
        case .semiPro: 1.2
        case .pro: 1.4
        }
    }
    /// 훈련이 "크리티컬"로 터질 확률과, 터졌을 때 오르는 양의 배수. 포인트는 똑같이 든다.
    public static let careerCriticalChance = 0.01
    public static let careerCriticalMultiplier = 3.0
    /// 추가 훈련(설정에서 켠다): 정해진 횟수를 넘긴 훈련은 한 번마다 비용이 이 배수만큼 더 든다 (1.5배, 2.25배, 3.4배…).
    public static let careerExtraSessionCost = 1.5

    /// 능력치 하나를 +1 올리는 데 드는 훈련 포인트.
    /// 훈련할 때마다 그 능력치의 다음 비용이 6%쯤 오른다 (25에서 12.5만, 50에서 58만, 70에서 199만, 85에서 500만).
    public static func careerTrainingCost(value: Double) -> Int {
        let cost = 125_000 * exp((value - 25) * 0.0615)
        // 훈련 한 번에 오르는 양이 작아서, 값이 조금 올라도 비용이 따라 오르는 것이 보이게 천 단위로 끊는다.
        return max(50_000, Int(cost / 1_000) * 1_000)
    }

    /// 그 리그에서 뛰는 동안 명성이 오를 수 있는 한도.
    public static func careerFameCap(_ tier: LeagueTier) -> Double {
        switch tier {
        case .citizenAmateur: 20
        case .citizenSemiPro: 30
        case .citizenPro: 40
        case .amateur: 55
        case .semiPro: 75
        case .pro: 100
        }
    }
}
