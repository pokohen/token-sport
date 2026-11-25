import Foundation

/// 이적 시장: 재계약, FA·이적 제안, 들어온 오퍼에 답하기.
extension Game {
    // MARK: 재계약

    /// 선수가 재계약 조건으로 요구하는 연봉과 기간.
    public func renewalDemand(_ player: Player) -> (salary: Int, years: Int) {
        let market = Balance.marketSalary(ability: player.ability)
        let performance = switch player.position.sport {
        case .football: Self.footballPerformance(player)
        // 1:1 대전의 기록은 선수 모드를 붙이는 단계에서 만든다.
        case .duel: 0.0
        case .baseball, .basketball: player.isPitcher
            ? Double(player.pitching.wins + player.pitching.saves) / 20
            : max(0, player.batting.ops - 0.7) * 0.5
        }
        let asked = max(Double(player.contract.salary) * 1.08, Double(market) * (1 + min(0.3, performance)))
        let years = player.age >= 32 ? 1 : player.age <= 25 ? 3 : 2
        return (Int(asked / 1_000) * 1_000, userTier.isCitizen ? min(years, 2) : years)
    }

    /// 재계약 제안. 계약 마지막 시즌 중 아무 때나, 그리고 오프시즌이 끝나기 전까지 할 수 있다.
    public mutating func proposeRenewal(_ id: PlayerID, salary: Int, years: Int) throws {
        guard let player = players[id], player.teamID == userTeamID else {
            throw GameError("내 팀 선수가 아닙니다.")
        }
        guard isExpiring(player) else { throw GameError("계약 마지막 시즌인 선수만 재계약할 수 있습니다.") }
        guard phase == .offseason || player.contract.seasonsLeft > 0 else {
            throw GameError("협상 기간이 끝났습니다. 선수의 역제안을 받아들일지만 정할 수 있습니다.")
        }
        guard (1...3).contains(years), salary > 0 else { throw GameError("조건이 올바르지 않습니다.") }
        guard !proposals.contains(where: { $0.playerID == id }) else {
            throw GameError("이미 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.")
        }
        counters.removeAll { $0.playerID == id }
        proposals.append(Proposal(
            id: newMarketID(), kind: .renewal, playerID: id, salary: salary, years: years, fee: 0))
    }

    // MARK: FA와 이적 제안

    /// FA 시장에 나와 있는 선수 (오프시즌에만 열린다).
    public var freeAgentMarket: [Player] {
        guard phase == .offseason else { return [] }
        return freeAgents.compactMap { players[$0] }
            .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
    }

    public mutating func proposeFreeAgent(_ id: PlayerID, salary: Int, years: Int) throws {
        // 축구의 무소속 선수는 이적 기간 밖에도 계약할 수 있다.
        let anytime = switch sport {
        case .football: true
        case .baseball, .basketball, .duel: false
        }
        guard phase == .offseason || anytime else {
            throw GameError("FA 영입은 오프시즌 이적 시장에서만 할 수 있습니다.")
        }
        guard let player = players[id], player.teamID == nil, freeAgents.contains(id) else {
            throw GameError("FA 선수가 아닙니다.")
        }
        guard (1...3).contains(years), salary > 0 else { throw GameError("조건이 올바르지 않습니다.") }
        guard !proposals.contains(where: { $0.playerID == id }) else {
            throw GameError("이미 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.")
        }
        try checkForeignLimit(player)
        try checkCanSpend(0)
        proposals.append(Proposal(
            id: newMarketID(), kind: .freeAgent, playerID: id, salary: salary, years: years, fee: 0))
    }

    /// 다른 구단 선수에게 이적 제안을 넣는다.
    public mutating func proposeTransfer(_ id: PlayerID, fee: Int) throws {
        guard tradeWindowOpen else { throw GameError("지금은 이적 시장이 닫혀 있습니다.") }
        guard let player = players[id], let team = player.teamID, team != userTeamID else {
            throw GameError("다른 구단 선수가 아닙니다.")
        }
        guard fee > 0 else { throw GameError("이적료를 입력해 주세요.") }
        guard !proposals.contains(where: { $0.playerID == id }) else {
            throw GameError("이미 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.")
        }
        try checkCanSpend(fee)
        proposals.append(Proposal(
            id: newMarketID(), kind: .transfer, playerID: id,
            salary: player.contract.salary, years: max(1, player.contract.seasonsLeft), fee: fee))
    }

    /// 선수가 내 팀에 올 마음이 있는지: 인지도, 리그, 제시 금액을 본다.
    func joinChance(_ player: Player, salary: Int) -> Double {
        let range = Balance.abilityRange(userTier)
        // 리그 수준을 한참 넘는 선수는 오지 않는다.
        if player.ability > range.upperBound + 5 { return 0 }
        let reference = max(100, Balance.requiredFame(from: userTier == .pro ? .semiPro : userTier))
        let fame = min(1, userTeam.fame / reference)
        let money = Double(salary) / Double(max(1, Balance.marketSalary(ability: player.ability))) - 1
        let reach = max(0, player.ability - mid(range)) * 0.01
        return clamp(0.35 + 0.4 * fame + 0.5 * money - reach, 0.03, 0.95)
    }

    /// 역제안을 받아들인다.
    public mutating func acceptCounter(_ id: Int) throws {
        guard let counter = counters.first(where: { $0.id == id }), let player = players[counter.playerID] else {
            throw GameError("제안을 찾을 수 없습니다.")
        }
        counters.removeAll { $0.id == id }
        players[player.id]?.contract = Contract(
            salary: counter.salary, seasonsLeft: counter.years + max(0, player.contract.seasonsLeft),
            relegationClause: player.contract.relegationClause)
        post("\(player.name)와(과) 재계약했습니다 (\(counter.years)시즌, 연봉 ₩\(counter.salary.formatted())).")
    }

    public mutating func declineCounter(_ id: Int) {
        counters.removeAll { $0.id == id }
    }

    public mutating func withdrawProposal(_ id: Int) {
        proposals.removeAll { $0.id == id }
    }

    // MARK: 들어온 오퍼에 답하기

    public mutating func respond(to offerID: Int, _ response: OfferResponse) throws {
        guard let index = offers.firstIndex(where: { $0.id == offerID }) else {
            throw GameError("오퍼를 찾을 수 없습니다.")
        }
        let offer = offers[index]
        guard let player = players[offer.playerID], player.teamID == userTeamID else {
            offers.remove(at: index)
            throw GameError("이미 팀을 떠난 선수입니다.")
        }
        let buyer = teams[offer.fromTeam]

        switch response {
        case .reject:
            offers.remove(at: index)
            post("\(buyer.name)의 \(player.name) 오퍼를 거절했습니다.")
        case .askMore:
            guard !offer.raised else { throw GameError("이미 한 번 올려 달라고 했습니다.") }
            if rng.chance(0.5) {
                offers[index].fee = Int(Double(offer.fee) * rng.double(1.15...1.3) / 1_000) * 1_000
                offers[index].raised = true
                post("\(buyer.name)이(가) \(player.name) 이적료를 ₩\(offers[index].fee.formatted())으로 올렸습니다.")
            } else {
                offers.remove(at: index)
                post("\(buyer.name)이(가) \(player.name) 오퍼를 거두었습니다.")
            }
        case .accept:
            guard !isMatchLive else { throw GameError("경기 중에는 선수를 보낼 수 없습니다.") }
            if offer.swapPlayerID == nil {
                // 선수를 팔고 나서도 경기를 치를 인원은 남아야 한다.
                guard canSpare(player.id) else { throw GameError("이 선수를 보내면 경기를 치를 인원이 모자랍니다.") }
            }
            offers.remove(at: index)
            add(player.id, to: buyer.id)
            teams[userTeamID].lineupOverride.removeAll { $0 == player.id }
            if offer.fee > 0 { funds.earn(offer.fee, .sales) }
            if let swapID = offer.swapPlayerID, players[swapID]?.teamID == buyer.id {
                add(swapID, to: userTeamID)
                post("트레이드 성사: \(player.name) ↔ \(players[swapID]?.name ?? "") (\(buyer.name))")
            } else {
                post("\(player.name)이(가) \(buyer.name)(으)로 이적했습니다. 이적료 ₩\(offer.fee.formatted()).")
            }
            offers.removeAll { $0.playerID == player.id }
            proposals.removeAll { $0.playerID == player.id }
            counters.removeAll { $0.playerID == player.id }
        }
    }
}
