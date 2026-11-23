import Foundation

/// 이적 시장: 경기가 끝날 때마다 제안에 답이 오고 새 오퍼가 들어온다.
extension Game {
    // MARK: 경기가 끝날 때마다

    mutating func resolveMarketAfterMatch() {
        guard !isBankrupt else { return }

        // 지난 경기 뒤에 온 오퍼에 답하지 않았으면 자동 거절
        for offer in offers {
            if let player = players[offer.playerID] {
                post("\(teams[offer.fromTeam].name)의 \(player.name) 오퍼가 답이 없어 사라졌습니다.")
            }
        }
        offers = []

        // 오프시즌 끝에 역제안 때문에 기다려 준 선수: 새 시즌 첫 경기까지 답이 없으면 떠난다.
        if phase == .regular {
            let gone = roster(of: userTeamID).filter { $0.contract.seasonsLeft <= 0 }
            for player in gone {
                moveToFreeAgency(player.id)
                counters.removeAll { $0.playerID == player.id }
            }
            if !gone.isEmpty {
                post("재계약하지 못해 떠난 선수: \(gone.map(\.name).joined(separator: ", "))")
                fillUserMinimumRoster()
            }
        }

        // 후보 만료
        for index in candidates.indices { candidates[index].matchesLeft -= 1 }
        for candidate in candidates where candidate.matchesLeft <= 0 { removePlayer(candidate.playerID) }
        candidates.removeAll { $0.matchesLeft <= 0 }

        // 스카우트 복귀
        if var trip = scoutTrip {
            trip.matchesLeft -= 1
            if trip.matchesLeft <= 0 {
                scoutTrip = nil
                scoutReturns(trip)
            } else {
                scoutTrip = trip
            }
        }

        // 내가 보낸 제안에 답이 온다
        let pending = proposals
        proposals = []
        for proposal in pending { answer(proposal) }

        // 새 오퍼
        guard tradeWindowOpen else { return }
        if phase == .offseason {
            // 마지막 친선 경기 뒤에는 곧바로 새 시즌이라 답할 틈이 없다.
            guard friendliesPlayed < Balance.friendliesPerOffseason else { return }
            // 오프시즌에는 경기가 끝날 때마다 오퍼가 들어온다. 강등됐으면 몰려온다.
            let count = relegatedThisOffseason ? rng.int(2...3) : 1
            generateIncomingOffers(count: count)
        } else if rng.chance(0.12) {
            generateIncomingOffers(count: 1)
        }
    }

    mutating func answer(_ proposal: Proposal) {
        guard let player = players[proposal.playerID] else { return }
        switch proposal.kind {
        case .renewal:
            guard player.teamID == userTeamID else { return }
            let demand = renewalDemand(player)
            let starter = sport == .football
                ? (currentFootballLineup.map { lineup in lineup.starters.contains { $0.id == player.id } } ?? true)
                : currentLineup.map { lineup in
                    lineup.batters.contains { $0.id == player.id } || lineup.starter == player.id
                        || lineup.bullpen.contains(player.id)
                } ?? true
            var chance = proposal.salary >= demand.salary
                ? 0.9 : 0.55 + (Double(proposal.salary) / Double(demand.salary) - 1) * 1.5
            if relegatedThisOffseason { chance -= 0.3 }
            if !starter { chance -= 0.15 }
            if rng.chance(clamp(chance, 0.02, 0.95)) {
                players[player.id]?.contract = Contract(
                    salary: proposal.salary, seasonsLeft: proposal.years + max(0, player.contract.seasonsLeft),
                    relegationClause: player.contract.relegationClause)
                post("\(player.name)이(가) 재계약에 합의했습니다 (\(proposal.years)시즌, 연봉 ₩\(proposal.salary.formatted())).")
            } else if rng.chance(0.6) {
                counters.append(Proposal(
                    id: newMarketID(), kind: .renewal, playerID: player.id,
                    salary: demand.salary, years: demand.years, fee: 0))
                let raise = Int((Double(demand.salary) / Double(max(1, player.contract.salary)) - 1) * 100)
                post("\(player.name)이(가) 재계약 조건으로 연봉 \(raise)% 인상(₩\(demand.salary.formatted()))을 요구합니다.")
            } else {
                post("\(player.name)이(가) 재계약 제안을 거절했습니다.")
            }

        case .freeAgent:
            guard player.teamID == nil, freeAgents.contains(player.id) else {
                post("FA \(player.name)은(는) 이미 다른 팀과 계약했습니다.")
                return
            }
            let full = userTeam.roster.count >= rosterLimit(userTier)
            let foreignOK = (try? checkForeignLimit(player)) != nil
            if !full, foreignOK, crisisMatchesLeft == nil, rng.chance(joinChance(player, salary: proposal.salary)) {
                add(player.id, to: userTeamID)
                players[player.id]?.contract = Contract(salary: proposal.salary, seasonsLeft: proposal.years)
                post("FA \(player.name)이(가) 우리 제안을 받아들였습니다.")
            } else {
                post("FA \(player.name)이(가) 우리 제안을 거절했습니다.")
            }

        case .transfer:
            guard let seller = player.teamID, seller != userTeamID else { return }
            let asking = Double(value(of: player)) * rng.double(1.1...1.5)
            let full = userTeam.roster.count >= rosterLimit(userTier)
            let affordable = funds.balance >= proposal.fee && crisisMatchesLeft == nil
            let foreignOK = (try? checkForeignLimit(player)) != nil
            if !full, affordable, foreignOK, Double(proposal.fee) >= asking,
               rng.chance(joinChance(player, salary: player.contract.salary) + 0.2) {
                funds.spend(proposal.fee, .recruit)
                teams[seller].funds += proposal.fee
                add(player.id, to: userTeamID)
                post("\(teams[seller].name)이(가) \(player.name) 이적에 합의했습니다. 이적료 ₩\(proposal.fee.formatted()).")
            } else {
                post("\(teams[seller].name)이(가) \(player.name) 이적 제안을 거절했습니다.")
            }
        }
    }

    /// 다른 구단이 내 선수에게 오퍼를 보낸다. 활약이 좋거나 잠재력이 높은 선수일수록 오퍼가 많다.
    mutating func generateIncomingOffers(count: Int) {
        guard count > 0 else { return }
        for _ in 0..<count {
            let mine = roster(of: userTeamID).filter { player in !offers.contains { $0.playerID == player.id } }
            guard !mine.isEmpty else { return }
            let weights = mine.map { pow(max(1, $0.ability + ($0.potential - $0.ability) * 0.5), 2) }
            let player = mine[rng.weighted(weights)]

            // 같은 리그나 상위 리그 구단이 관심을 보인다.
            let buyers = teams.filter {
                !$0.isUser && $0.tier <= userTier && $0.tier.rawValue >= userTier.rawValue - 1
            }
            guard !buyers.isEmpty else { return }
            let buyer = rng.pick(buyers)
            let fee = Int(Double(value(of: player)) * rng.double(0.9...1.4) / 1_000) * 1_000

            // 시즌 중에는 선수 ↔ 선수 트레이드 제안도 온다.
            var swap: PlayerID?
            if phase == .regular, rng.chance(0.4) {
                swap = roster(of: buyer.id)
                    .filter {
                        (sport != .baseball ? $0.position == player.position : $0.isPitcher == player.isPitcher)
                            && abs($0.ability - player.ability) <= 6
                    }
                    .min { (abs($0.ability - player.ability), $0.id) < (abs($1.ability - player.ability), $1.id) }?.id
            }
            offers.append(TransferOffer(
                id: newMarketID(), playerID: player.id, fromTeam: buyer.id,
                fee: swap == nil ? max(fee, 1_000) : 0, swapPlayerID: swap))
            if let swap, let other = players[swap] {
                post("\(buyer.name)이(가) 트레이드를 제안했습니다: \(player.name) ↔ \(other.name)")
            } else {
                post("\(buyer.name)이(가) \(player.name)에게 ₩\(max(fee, 1_000).formatted()) 이적 오퍼를 보냈습니다.")
            }
        }
    }
}
