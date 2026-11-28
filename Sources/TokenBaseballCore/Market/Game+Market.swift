import Foundation

/// 이적 시장: 영입 후보, 스카우트, 방출.
extension Game {
    mutating func newMarketID() -> Int {
        nextMarketID += 1
        return nextMarketID
    }

    func value(of player: Player) -> Int {
        Balance.transferValue(ability: player.ability, potential: player.potential, age: player.age)
    }

    func checkRosterRoom() throws {
        guard userTeam.roster.count < rosterLimit(userTier) else {
            throw GameError(String(localized: "로스터가 가득 찼습니다 (\(rosterLimit(userTier))명). 선수를 내보내야 영입할 수 있습니다."))
        }
    }

    func checkForeignLimit(_ player: Player) throws {
        guard player.isForeign else { return }
        guard userTier <= .semiPro else { throw GameError(String(localized: "외국인 선수는 1~2부에서만 영입할 수 있습니다.")) }
        let count = roster(of: userTeamID).filter(\.isForeign).count
        guard count < Balance.foreignPlayerLimit else {
            throw GameError(String(localized: "외국인 선수는 팀당 \(Balance.foreignPlayerLimit)명까지입니다."))
        }
    }

    // MARK: 입단 테스트

    public var tryoutFee: Int { price(Balance.tryoutFee(userTier)) }

    /// 돈을 내고 테스트를 열면 지역 선수 후보 3~5명이 온다.
    public mutating func holdTryout() throws {
        guard !candidates.contains(where: { $0.source == .tryout }) else {
            throw GameError(String(localized: "지난 테스트 후보가 아직 남아 있습니다."))
        }
        let cost = tryoutFee
        try checkCanSpend(cost)
        funds.spend(cost, .recruit)

        let tier = userTier
        let range = Balance.abilityRange(tier)
        let count = rng.int(3...5) + (youthBoost > 0 ? 2 : 0)
        for _ in 0..<count {
            var spec = PlayerFactory.Spec(
                position: rng.pick(rosterPositions(tier)), tier: tier, season: season)
            // 싸고 능력치가 낮지만, 잠재력이 높은 선수가 가끔 섞여 있다.
            spec.ability = range.lowerBound...(range.lowerBound + (range.upperBound - range.lowerBound) * 0.6)
            if rng.chance(youthBoost > 0 ? 0.35 : 0.15) {
                spec.age = 18...22
                spec.potential = (range.upperBound - 5)...(range.upperBound + 15)
            }
            let player = makePlayer(spec)
            candidates.append(Candidate(
                id: newMarketID(), playerID: player.id, fee: 0, matchesLeft: 1, source: .tryout))
        }
        if youthBoost > 0 { youthBoost -= 1 }
        post("입단 테스트에 \(count)명이 왔습니다. 다음 경기가 끝나기 전에 계약하세요.")
    }

    // MARK: 스카우트

    public func scoutCost(_ region: ScoutRegion) -> Int {
        price(Balance.tryoutFee(userTier) * region.costFactor)
    }

    /// 지역을 정해 스카우트를 보낸다. 몇 경기 뒤 후보 목록이 온다.
    public mutating func sendScout(_ region: ScoutRegion) throws {
        guard userTeam.scoutLevel >= 1 else { throw GameError(String(localized: "스카우트 시설이 필요합니다.")) }
        guard scoutTrip == nil else { throw GameError(String(localized: "스카우트가 이미 나가 있습니다.")) }
        if region == .overseas, userTier > .semiPro {
            throw GameError(String(localized: "해외 스카우트는 1~2부에서만 보낼 수 있습니다."))
        }
        let cost = scoutCost(region)
        try checkCanSpend(cost)
        funds.spend(cost, .recruit)
        scoutTrip = ScoutTrip(region: region, matchesLeft: 3, cost: cost)
        post("\(region.rawValue) 스카우트를 보냈습니다. 3경기 뒤에 돌아옵니다.")
    }

    mutating func scoutReturns(_ trip: ScoutTrip) {
        let tier = userTier
        let range = Balance.abilityRange(tier)
        let level = userTeam.scoutLevel
        let count = 3 + level / 2
        let lift: Double = trip.region == .local ? 0 : trip.region == .national ? 4 : 8
        for _ in 0..<count {
            var spec = PlayerFactory.Spec(
                position: rng.pick(rosterPositions(tier)), tier: tier, season: season)
            let low = range.lowerBound + lift + Double(level)
            spec.ability = low...(range.upperBound + lift)
            spec.foreign = trip.region == .overseas
            if !spec.foreign, rng.chance(0.15 + 0.05 * Double(level)) {
                spec.age = 18...23
                spec.potential = (range.upperBound)...(range.upperBound + 18)
            }
            let player = makePlayer(spec)
            let fee = Balance.marketSalary(ability: player.ability) / 2
            candidates.append(Candidate(
                id: newMarketID(), playerID: player.id, fee: fee, matchesLeft: 2, source: .scout))
        }
        post("\(trip.region.rawValue) 스카우트가 후보 \(count)명을 데려왔습니다.")
    }

    /// 후보와 계약한다.
    public mutating func sign(candidate id: Int) throws {
        guard let candidate = candidates.first(where: { $0.id == id }),
              let player = players[candidate.playerID]
        else { throw GameError(String(localized: "후보를 찾을 수 없습니다.")) }
        try checkRosterRoom()
        try checkForeignLimit(player)
        let fee = price(candidate.fee)
        try checkCanSpend(fee)
        funds.spend(fee, .recruit)
        add(player.id, to: userTeamID)
        candidates.removeAll { $0.id == id }
        if candidate.source == .draft {
            // 드래프트는 한 명만 지명한다.
            for other in candidates where other.source == .draft { removePlayer(other.playerID) }
            candidates.removeAll { $0.source == .draft }
        }
        post("\(player.name)(\(player.position.label))와(과) 계약했습니다.")
    }

    // MARK: 방출

    public mutating func release(_ id: PlayerID) throws {
        guard let player = players[id], player.teamID == userTeamID else {
            throw GameError(String(localized: "내 팀 선수가 아닙니다."))
        }
        guard !isMatchLive else { throw GameError(String(localized: "경기 중에는 방출할 수 없습니다.")) }
        guard canSpare(id) else {
            let need = switch sport {
            case .football: String(localized: "골키퍼 1명을 포함해 \(Balance.footballStarters)명은 남아 있어야 합니다.")
            case .duel: String(localized: "선수 \(DuelLineupBuilder.setsPerMatch)명은 남아 있어야 합니다.")
            case .baseball, .basketball: String(localized: "야수 \(Balance.minBatters)명, 투수 \(Balance.minPitchers)명은 남아 있어야 합니다.")
            }
            throw GameError(need)
        }
        moveToFreeAgency(id)
        offers.removeAll { $0.playerID == id }
        proposals.removeAll { $0.playerID == id }
        counters.removeAll { $0.playerID == id }
        // 오래 뛴 선수를 방출하면 인지도가 조금 떨어진다.
        if season - player.joinedSeason >= 3 {
            teams[userTeamID].fame = max(0, teams[userTeamID].fame - 5)
            post("\(player.name) 방출. 오래 뛴 선수를 내보내 인지도가 조금 떨어졌습니다.")
        } else {
            post("\(player.name) 방출.")
        }
    }
}

extension Game {
    /// 이 선수의 이적료 시장가.
    public func value(for player: Player) -> Int { value(of: player) }
}

extension Game {
    /// 화면 확인용: 오퍼를 하나 만든다.
    public mutating func generateDemoOffer() {
        generateIncomingOffers(count: 1)
    }
}
