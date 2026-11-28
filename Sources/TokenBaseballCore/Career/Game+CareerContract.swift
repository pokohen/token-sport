import Foundation

/// 선수 모드: 이적·재계약·입단 제안과 그에 대한 답.
extension Game {
    // MARK: 계약 제안

    /// 그 구단에 갔을 때의 입지: 같은 포지션 선수들과 능력을 비교한다.
    public func careerRole(on team: TeamID) -> CareerRole {
        guard let me = myPlayer else { return .prospect }
        let peers = roster(of: team).filter { $0.position == me.position && $0.id != me.id }
            .map(\.ability).sorted(by: >)
        let slots: Int
        switch me.position {
        case .starter: slots = Balance.starterRest(teams[team].tier) + 1
        case .reliever: slots = max(1, peers.count)
        case .goalkeeper, .defender, .midfielder, .forward:
            slots = formation(of: team).slots.filter { $0 == me.position }.count
        default: slots = 1
        }
        guard peers.count >= slots else { return .starter }
        let bar = peers[slots - 1]
        if me.ability >= bar { return .starter }
        return me.ability >= bar - 6 ? .rotation : .prospect
    }

    mutating func newCareerOfferID() -> Int {
        let id = career?.nextOfferID ?? 1
        career?.nextOfferID = id + 1
        return id
    }

    /// 경기가 끝날 때마다: 답하지 않은 제안은 사라지고, 이적 기간이면 관심이 쌓인 구단이 제안할 수 있다.
    mutating func resolveCareerMarketAfterMatch() {
        guard var career, !career.retired, players[career.playerID] != nil else { return }
        var kept: [CareerOffer] = []
        var expired: [TeamID] = []
        for var offer in career.offers {
            guard offer.kind == .transfer else { kept.append(offer); continue }
            offer.matchesLeft -= 1
            if offer.matchesLeft > 0 {
                kept.append(offer)
            } else {
                expired.append(offer.teamID)
                post("\(teams[offer.teamID].name)의 이적 제안이 답이 없어 사라졌습니다.")
            }
        }
        career.offers = kept
        if !tradeWindowOpen { career.transferRequested = false }
        self.career = career
        for team in expired { coolCareerScout(team) }

        guard !career.isFreeAgent, tradeWindowOpen else { return }
        // 마지막 친선 경기 뒤에는 곧바로 새 시즌이라 답할 틈이 없다.
        if phase == .offseason, friendliesPlayed >= Balance.friendliesPerOffseason { return }
        guard career.matchesAtClub >= Balance.careerOfferCooldown,
              career.offers.filter({ $0.kind == .transfer }).isEmpty
        else { return }
        // 제안은 관심이 충분히 쌓인 스카우트의 구단에서 온다.
        if let scout = careerScoutReadyToOffer() { makeCareerTransferOffer(from: scout) }
    }

    /// 나를 지켜보던 구단이 제안한다. 관심이 클수록 연봉을 더 부른다.
    mutating func makeCareerTransferOffer(from scout: CareerScout) {
        guard let me = myPlayer, let myTeam = me.teamID else { return }
        let team = scout.teamID
        let upward = teams[team].tier < teams[myTeam].tier
        let bump = (upward ? 1.3 : 1.1) + max(0, scout.interest - Balance.careerScoutOfferInterest) / 200
        let base = max(me.contract.salary, Balance.marketSalary(ability: me.ability))
        let salary = Int(Double(base) * bump * rng.double(1.0...1.15) / 1_000) * 1_000
        let offer = CareerOffer(
            id: newCareerOfferID(), kind: .transfer, teamID: team, salary: salary,
            years: rng.int(1...3), role: careerRole(on: team), matchesLeft: 1)
        self.career?.offers.append(offer)
        post("\(teams[team].tier.displayName(for: sport)) \(teams[team].name)에서 이적 제안이 왔습니다. 다음 경기가 끝나기 전에 답하세요.")
    }

    /// 무소속이 됐을 때 받는 입단 제안. 지금 능력에 맞는 리그의 구단 두세 곳이다.
    mutating func makeCareerTryoutOffers() -> [CareerOffer] {
        guard let me = myPlayer else { return [] }
        let lastTier = teams[userTeamID].tier
        // 리그 강도의 가운데가 내 능력과 가장 가까운 리그. 방출된 선수가 윗 리그로 올라가지는 않는다.
        var fit = LeagueTier.allCases.min {
            abs(mid(Balance.strengthRange($0)) - me.ability) < abs(mid(Balance.strengthRange($1)) - me.ability)
        } ?? lastTier
        if fit < lastTier { fit = lastTier }
        var offers: [CareerOffer] = []
        for (tier, count) in [(fit, 2), (fit.lower ?? fit, 1)] {
            let pool = rng.shuffled(teams(in: tier).filter { team in
                team.id != userTeamID && !offers.contains { $0.teamID == team.id }
            })
            for team in pool.prefix(count) {
                offers.append(CareerOffer(
                    id: newCareerOfferID(), kind: .tryout, teamID: team.id,
                    salary: Balance.marketSalary(ability: me.ability), years: rng.int(1...2),
                    role: careerRole(on: team.id), matchesLeft: 99))
            }
        }
        return offers
    }

    // MARK: 제안에 답하기

    public mutating func acceptCareerOffer(_ id: Int) throws {
        guard !isMatchLive else { throw GameError(String(localized: "경기가 끝난 뒤에 답할 수 있습니다.")) }
        guard let career, !career.retired, let offer = career.offers.first(where: { $0.id == id }),
              let me = players[career.playerID]
        else { throw GameError(String(localized: "이미 사라진 제안입니다.")) }

        let club = teams[offer.teamID]
        if offer.kind == .renewal {
            players[me.id]?.contract = Contract(salary: offer.salary, seasonsLeft: offer.years)
            post("\(club.name)과(와) \(offer.years)시즌 재계약했습니다. 연봉 ₩\(offer.salary.formatted()).")
        } else {
            // 소속이 생긴 것으로 먼저 적어야, 구단에 들어갈 때 라이벌이 새 리그에 맞게 정해진다.
            let wasFreeAgent = career.isFreeAgent
            // 시즌 도중에 옮기면 지금까지의 기록은 옛 구단의 몫으로 남기고, 새 리그에서는 0부터 센다.
            let midSeason = phase == .regular && !career.seasonClosed
            if midSeason, !wasFreeAgent { splitCareerSeason() }
            self.career?.isFreeAgent = false
            joinCareerClub(offer.teamID)
            // 새 구단에서는 처음부터 다시 눈에 띄어야 한다.
            clearCareerScouts()
            players[me.id]?.contract = Contract(salary: offer.salary, seasonsLeft: offer.years)
            self.career?.trust = Balance.careerStartTrust
            // e스포츠: 세트 보장은 새 팀의 경기 수로 센다 (옛 팀의 경기 번호가 남아 있으면 한참 나오지 못한다).
            if me.position.sport == .duel { players[me.id]?.lastStartGame = -99 }
            // 시즌 목표는 새 구단 기준으로, 남은 경기만큼 다시 받는다.
            if midSeason { assignCareerGoal(announce: true, remaining: remainingSeasonShare) }
            post("\(club.tier.displayName(for: sport)) \(club.name)(으)로 옮겼습니다. \(offer.years)시즌, 연봉 ₩\(offer.salary.formatted()). 예상 입지: \(offer.role.rawValue).")
        }
        self.career?.offers = []
        self.career?.transferRequested = false
    }

    public mutating func declineCareerOffer(_ id: Int) throws {
        guard let offer = career?.offers.first(where: { $0.id == id }) else { return }
        guard offer.kind != .tryout else { throw GameError(String(localized: "입단 제안 중 하나는 골라야 합니다.")) }
        career?.offers.removeAll { $0.id == id }
        if offer.kind == .transfer { coolCareerScout(offer.teamID) }
        post("\(teams[offer.teamID].name)의 \(offer.kind == .renewal ? "재계약" : "이적") 제안을 거절했습니다.")
    }

    /// 연봉을 올려 달라고 한다. 제안마다 한 번만 할 수 있고, 이적 제안은 거절당하면 사라진다.
    public mutating func negotiateCareerOffer(_ id: Int) throws {
        guard let career, let index = career.offers.firstIndex(where: { $0.id == id }) else {
            throw GameError(String(localized: "이미 사라진 제안입니다."))
        }
        var offer = career.offers[index]
        guard !offer.negotiated else { throw GameError(String(localized: "이미 한 번 요구했습니다.")) }
        offer.negotiated = true
        let name = teams[offer.teamID].name
        if rng.chance(min(0.9, 0.45 + career.fame / 200)) {
            offer.salary = Int(Double(offer.salary) * 1.15 / 1_000) * 1_000
            self.career?.offers[index] = offer
            post("\(name)이(가) 연봉을 ₩\(offer.salary.formatted())(으)로 올려 주었습니다.")
        } else if offer.kind == .transfer {
            self.career?.offers.remove(at: index)
            coolCareerScout(offer.teamID)
            post("\(name)이(가) 연봉 인상을 거절하고 제안을 거두었습니다.")
        } else {
            self.career?.offers[index] = offer
            post("\(name)이(가) 연봉 인상을 거절했습니다. 처음 조건은 그대로입니다.")
        }
    }

    /// 이적 요청: 제안이 올 확률이 오르지만 감독 신뢰가 떨어진다. 이적 기간마다 한 번.
    public mutating func requestCareerTransfer() throws {
        guard let career, !career.retired, !career.isFreeAgent else { throw GameError(String(localized: "지금은 요청할 수 없습니다.")) }
        guard tradeWindowOpen else { throw GameError(String(localized: "이적 기간이 아닙니다.")) }
        guard !career.transferRequested else { throw GameError(String(localized: "이번 이적 기간에 이미 요청했습니다.")) }
        self.career?.transferRequested = true
        if career.fans == nil { self.career?.trust = max(0, career.trust - 10) }
        // 소문이 돈다: 지켜보던 구단들의 관심이 오르고, 제안의 문턱이 낮아지고, 새 스카우트가 더 잘 온다.
        if var scouts = self.career?.scouts {
            for index in scouts.indices {
                scouts[index].interest = min(100, scouts[index].interest + Balance.careerScoutRequestBoost)
                scouts[index].lastChange = Balance.careerScoutRequestBoost
            }
            self.career?.scouts = scouts
        }
        post("구단에 이적을 요청했습니다. 감독 신뢰 −10. 스카우트들의 관심이 오르고, 제안이 더 쉽게 옵니다.")
    }
}
