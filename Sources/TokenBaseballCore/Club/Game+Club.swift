import Foundation

/// 홍보: 돈을 내고 인지도를 바로 올린다. 같은 홍보는 쓸수록 효과가 줄어든다 (시즌마다 초기화).
public enum Promotion: String, Codable, CaseIterable, Sendable {
    case flyer = "전단지"
    case newspaper = "지역 신문 광고"
    case sns = "SNS 캠페인"
    case festival = "지역 축제 참가"
    case youthClinic = "유소년 야구 교실"
    case tv = "TV 광고"

    public func label(_ sport: Sport) -> String {
        self == .youthClinic && sport == .football ? "유소년 축구 교실" : rawValue
    }

    public var cost: Int {
        switch self {
        case .flyer: 500_000
        case .newspaper: 3_000_000
        case .sns: 10_000_000
        case .festival: 20_000_000
        case .youthClinic: 30_000_000
        case .tv: 100_000_000
        }
    }

    public var fame: Double {
        switch self {
        case .flyer: 5
        case .newspaper: 20
        case .sns: 50
        case .festival: 80
        case .youthClinic: 60
        case .tv: 300
        }
    }

    public var note: String {
        switch self {
        case .festival: "시즌 중 1회"
        case .youthClinic: "다음 입단 테스트에 유망주 후보가 늘어남"
        case .tv: "3부 이상"
        default: ""
        }
    }
}

public enum FinancialState: Equatable, Sendable {
    case healthy
    /// 자금이 다음 5경기 연봉보다 적다.
    case warning
    /// 자금이 0 아래. 남은 유예 경기 수.
    case crisis(matchesLeft: Int)
    case bankrupt
}

public enum Facility: String, CaseIterable, Sendable {
    case training = "훈련소", stadium = "경기장", scout = "스카우트"
}

extension Game {
    // MARK: 재정 상태

    public var financialState: FinancialState {
        if isBankrupt { return .bankrupt }
        if let left = crisisMatchesLeft { return .crisis(matchesLeft: left) }
        if funds.balance < salaryPerMatch * Balance.warningMatches { return .warning }
        return .healthy
    }

    /// 위기 중에는 시설 업그레이드와 영입을 할 수 없다.
    func checkCanSpend(_ cost: Int) throws {
        guard !isBankrupt else { throw GameError("구단이 해체되었습니다.") }
        guard crisisMatchesLeft == nil else {
            throw GameError("재정 위기 중에는 시설 업그레이드와 영입을 할 수 없습니다.")
        }
        guard funds.balance >= cost else {
            throw GameError("자금이 모자랍니다. ₩\(cost.formatted())이 필요합니다.")
        }
    }

    /// 경기가 끝날 때마다: 위기 유예를 세고, 끝나면 파산한다.
    mutating func updateFinancialState() {
        guard !isBankrupt else { return }
        if funds.balance >= 0 {
            if crisisMatchesLeft != nil { post("재정 위기에서 벗어났습니다.") }
            crisisMatchesLeft = nil
            return
        }
        if let left = crisisMatchesLeft {
            if left <= 1 {
                goBankrupt()
            } else {
                crisisMatchesLeft = left - 1
                post("재정 위기: 유예 \(left - 1)경기 남았습니다.")
            }
        } else {
            crisisMatchesLeft = Balance.bankruptcyGraceMatches
            post("재정 위기! 자금이 0 아래로 떨어졌습니다. \(Balance.bankruptcyGraceMatches)경기 안에 메우지 못하면 구단이 해체됩니다.")
        }
    }

    /// 자금이 0 이상으로 돌아오면 (토큰 수입 등) 위기를 푼다. 경기 사이에도 부른다.
    public mutating func refreshFinancialState() {
        if !isBankrupt, crisisMatchesLeft != nil, funds.balance >= 0 {
            crisisMatchesLeft = nil
            post("재정 위기에서 벗어났습니다.")
        }
    }

    // MARK: 파산과 새 구단

    mutating func goBankrupt() {
        let old = userTeam
        let star = roster(of: old.id).max { ($0.ability, $0.id) < ($1.ability, $1.id) }?.name
        hallOfFame.append(HallEntry(
            name: old.name, foundedSeason: old.foundedSeason, endedSeason: season,
            bestTier: bestTier, star: star))
        post("\(old.name) 파산. 구단이 해체되었습니다. 기록은 명예의 전당에 남습니다.")

        // 선수들은 FA 시장으로 나가고, 빈자리는 새 CPU 구단이 채운다.
        for id in old.roster { moveToFreeAgency(id) }
        let taken = Set(teams.map(\.name))
        let identity = NameGenerator.cpuTeam(tier: old.tier, taken: taken, sport: sport, &rng)
        var replacement = Team(
            id: old.id, name: identity.name, city: identity.city, tier: old.tier, isUser: false, season: season)
        replacement.gamesPlayed = old.gamesPlayed
        teams[old.id] = replacement
        setUpCPUTeam(old.id, slot: 5)

        isBankrupt = true
        crisisMatchesLeft = nil
        live = nil
        liveFootball = nil
        liveBasketball = nil
        offers = []
        proposals = []
        counters = []
        for candidate in candidates { removePlayer(candidate.playerID) }
        candidates = []
        scoutTrip = nil
        appliedForPromotion = false
    }

    /// 파산 뒤 새 시민 구단을 만든다. 세계(CPU 팀, 리그 기록)는 그대로 이어진다.
    public mutating func foundNewClub(setup: ClubSetup, now: Date) throws {
        guard isBankrupt else { throw GameError("지금은 새 구단을 만들 수 없습니다.") }
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GameError("팀 이름을 입력해 주세요.") }
        guard !teams.contains(where: { $0.name == name }) else { throw GameError("이미 있는 팀 이름입니다.") }

        // 6부에서 가장 성적이 나쁜 CPU 구단 자리를 이어받는다.
        let tier = LeagueTier.citizenAmateur
        guard let slot = rankedStandings(tier).last(where: { !teams[$0.teamID].isUser })?.teamID else {
            throw GameError("새 구단이 들어갈 자리가 없습니다.")
        }
        for id in teams[slot].roster { moveToFreeAgency(id) }
        var team = Team(id: slot, name: name, city: setup.city, tier: tier, isUser: true, season: season)
        team.colorIndex = setup.colorIndex
        team.emblemIndex = setup.emblemIndex
        team.gamesPlayed = teams[slot].gamesPlayed
        teams[slot] = team
        userTeamID = slot
        fillUserStartRoster()
        if let row = standings[tier.index].firstIndex(where: { $0.teamID == slot }) {
            standings[tier.index][row] = StandingRow(teamID: slot)
        }

        funds = FundsLedger(startedAt: now)
        isBankrupt = false
        bestTier = tier
        promotionUses = [:]
        sponsorPenaltySeasons = 0
        relegatedThisOffseason = false
        youthBoost = 0
        lastResult = nil
        charges = max(charges, 1)
        chargeAnchor = now
        post("\(name) 창단! \(tier.displayName) 리그에서 다시 시작합니다.")
    }

    // MARK: 시설

    public func facilityLevel(_ facility: Facility) -> Int {
        switch facility {
        case .training: userTeam.trainingLevel
        case .stadium: userTeam.stadiumLevel
        case .scout: userTeam.scoutLevel
        }
    }

    /// 다음 레벨 업그레이드 비용. 최고 레벨이면 nil.
    public func upgradeCost(_ facility: Facility) -> Int? {
        let level = facilityLevel(facility)
        switch facility {
        case .training:
            return level < Balance.maxFacilityLevel ? price(Balance.trainingCost[level - 1]) : nil
        case .stadium:
            return level < Balance.maxFacilityLevel ? price(Balance.stadiumCost[level - 1]) : nil
        case .scout:
            return level < Balance.maxScoutLevel ? price(Balance.scoutCost[level]) : nil
        }
    }

    public mutating func upgrade(_ facility: Facility) throws {
        guard let cost = upgradeCost(facility) else { throw GameError("이미 최고 레벨입니다.") }
        try checkCanSpend(cost)
        funds.spend(cost, .facility)
        switch facility {
        case .training:
            teams[userTeamID].trainingLevel += 1
            post("훈련소 Lv\(userTeam.trainingLevel): \(Balance.trainingNames(sport)[userTeam.trainingLevel - 1])")
        case .stadium:
            teams[userTeamID].stadiumLevel += 1
            let fame = Balance.stadiumFamePerLevel * Double(userTeam.stadiumLevel)
            teams[userTeamID].fame += fame
            post("경기장 Lv\(userTeam.stadiumLevel): \(Balance.stadiumNames(sport)[userTeam.stadiumLevel - 1]). 인지도 +\(Int(fame)).")
        case .scout:
            teams[userTeamID].scoutLevel += 1
            post("스카우트 시설 Lv\(userTeam.scoutLevel)")
        }
    }

    // MARK: 홍보

    /// 이번에 하면 오를 인지도 (쓸수록 줄어든다).
    public func promotionEffect(_ promotion: Promotion) -> Double {
        let uses = promotionUses[promotion.rawValue] ?? 0
        return (promotion.fame * pow(0.8, Double(uses))).rounded()
    }

    public func promotionBlockedReason(_ promotion: Promotion) -> String? {
        if promotion == .tv, userTier > .amateur { return "3부 이상에서 할 수 있습니다." }
        if promotion == .festival {
            if phase != .regular { return "시즌 중에만 참가할 수 있습니다." }
            if (promotionUses[promotion.rawValue] ?? 0) >= 1 { return "이번 시즌에 이미 참가했습니다." }
        }
        return nil
    }

    public mutating func promote(_ promotion: Promotion) throws {
        if let reason = promotionBlockedReason(promotion) { throw GameError(reason) }
        let cost = price(promotion.cost)
        try checkCanSpend(cost)
        let effect = promotionEffect(promotion)
        funds.spend(cost, .promotion)
        teams[userTeamID].fame += effect
        promotionUses[promotion.rawValue, default: 0] += 1
        if promotion == .youthClinic { youthBoost += 1 }
        post("\(promotion.rawValue) 진행. 인지도 +\(Int(effect)).")
    }

    // MARK: 승강 플레이오프 신청

    public var promotionRequirement: (fame: Double, fee: Int)? {
        guard userTier != .pro else { return nil }
        return (Balance.requiredFame(from: userTier), price(Balance.applicationFee(from: userTier)))
    }

    public mutating func applyForPromotion() throws {
        guard sport != .football else {
            throw GameError("축구는 신청이 필요 없습니다. 순위와 구장 등급으로 승격이 정해집니다.")
        }
        guard let requirement = promotionRequirement else { throw GameError("이미 최상위 리그입니다.") }
        guard phase == .regular else { throw GameError("정규시즌 중에만 신청할 수 있습니다.") }
        guard !appliedForPromotion else { throw GameError("이미 신청했습니다.") }
        guard round < Balance.applicationDeadlineRound else {
            throw GameError("신청 마감(\(Balance.applicationDeadlineRound)라운드)이 지났습니다.")
        }
        guard userTeam.fame >= requirement.fame else {
            throw GameError("인지도가 모자랍니다. \(Int(requirement.fame)) 이상이어야 합니다.")
        }
        try checkCanSpend(requirement.fee)
        funds.spend(requirement.fee, .fee)
        appliedForPromotion = true
        post("승강 플레이오프를 신청했습니다. 시즌이 끝났을 때 순위로 진출 여부가 정해집니다.")
    }
}
