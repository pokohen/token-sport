import Foundation

/// 시즌 흐름: 정규시즌 → 시상 → 승강 플레이오프 → 오프시즌 → 다음 시즌.
extension Game {
    // MARK: 정규시즌 끝

    mutating func endRegularSeason() {
        for tier in LeagueTier.allCases {
            for row in standings[tier.index] {
                lastWinRate[row.teamID] = sport == .football
                    ? Double(row.points) / Double(max(1, row.games * 3)) : row.winRate
            }
        }
        giveAwards()
        closeCareerSeason()
        // 강등 뒤 스폰서 감소는 한 시즌 동안 이어지고 여기서 끝난다.
        if sponsorPenaltySeasons > 0 { sponsorPenaltySeasons -= 1 }

        // 순위 상금. 시즌 도중에 다시 창단한 구단은 치른 경기가 적어 순위 상금을 받지 않는다.
        let myRank = rank(of: userTeamID)
        let myGames = standings[userTier.index].first { $0.teamID == userTeamID }.map { $0.wins + $0.losses + $0.draws } ?? 0
        let fullSeason = myGames >= roundsPerSeason / 2
        let prize = isCareer || isBankrupt || !fullSeason ? 0 : Balance.prizeMoney(userTier, rank: myRank)
        if !isBankrupt {
            post("정규시즌 종료. \(userTeam.name)은(는) \(userTier.displayName) \(myRank)위로 마쳤습니다.")
            if !isCareer, !fullSeason, Balance.prizeMoney(userTier, rank: myRank) > 0 {
                post("시즌 도중에 창단해 이번 시즌 순위 상금은 없습니다.")
            }
        }
        if prize > 0 {
            funds.earn(prize, .prize)
            post("순위 상금 ₩\(prize.formatted())을 받았습니다.")
        }

        // 승강: 리그 경계마다 자동 승격·강등과 플레이오프를 정한다.
        setUpPlayoffs()

        if !isCareer, !isBankrupt, userTier != .pro, !canPromote(userTeamID), myRank <= (sport == .football ? Balance.footballAutoPromotions(teams: teams(in: userTier).count) + 4 : 3) {
            post(sport == .football
                ? "구장 등급이 모자라 승격 자격이 다음 순위 팀으로 넘어갔습니다. 경기장을 Lv\(Balance.promotionStadiumLevel(from: userTier))까지 올려야 합니다."
                : "승강 플레이오프를 신청하지 않아 승격 자격이 다음 순위 팀으로 넘어갔습니다.")
        }

        // 내 팀이 없는 대진은 바로 치른다.
        resolveCPUSeries()

        if let mine = series.first(where: { !$0.isDecided && $0.involves(userTeamID) }), !isBankrupt {
            phase = .playoff
            post("\(mine.nextLabel.replacingOccurrences(of: " 1차전", with: ""))에 나갑니다.")
        } else {
            phase = .playoff
            advancePlayoffs()
        }
    }

    /// 플레이오프가 모두 끝났다: 정해진 승격·강등을 적용하고 오프시즌으로 넘어간다.
    mutating func finishPlayoffs() {
        series = []
        relegatedThisOffseason = false

        for move in pendingMoves {
            let from = teams[move.team].tier
            teams[move.team].tier = move.to
            if isCareer, move.team == userTeamID { careerClubMoved(from: from, to: move.to) }
            guard teams[move.team].isUser else { continue }
            if move.to < from {
                userPromoted(to: move.to)
            } else {
                userRelegated(to: move.to)
            }
        }
        pendingMoves = []
        startOffseason()
    }

    mutating func userPromoted(to tier: LeagueTier) {
        let grant = Balance.promotionGrant(to: tier)
        let fame = Balance.famePromotion(to: tier)
        funds.earn(grant, .prize)
        teams[userTeamID].fame += fame
        if tier < bestTier { bestTier = tier }
        post("승격! 다음 시즌은 \(tier.displayName) 리그입니다. 승격 지원금 ₩\(grant.formatted()), 인지도 +\(Int(fame)).")

        // 승격하면 연봉이 리그에 맞춰 한 번 더 오른다.
        for id in teams[userTeamID].roster {
            guard var player = players[id] else { continue }
            player.contract.salary = Int(Double(player.contract.salary) * 1.1)
            players[id] = player
        }
        // 프랜차이즈 스타: 시민 구단 때부터 함께한 선수가 프로 리그까지 왔다.
        if tier == .pro {
            for id in teams[userTeamID].roster {
                guard var player = players[id], player.joinedTier >= 4, !player.isFranchiseStar else { continue }
                player.isFranchiseStar = true
                players[id] = player
                teams[userTeamID].fame += Balance.fameFranchiseStar
                post("\(player.name), 시민 구단 시절부터 함께해 프로까지 온 프랜차이즈 스타가 되었습니다. 인지도 +\(Int(Balance.fameFranchiseStar)).")
            }
        }
    }

    mutating func userRelegated(to tier: LeagueTier) {
        relegatedThisOffseason = true
        sponsorPenaltySeasons = 1
        teams[userTeamID].fame *= 1 - Balance.fameRelegationDrop
        post("강등되었습니다. 다음 시즌은 \(tier.displayName) 리그입니다. 인지도가 크게 떨어지고 스폰서 수입이 줄어듭니다.")

        // 해외 스카우트는 1~2부에서만 쓸 수 있다. 나가 있던 스카우트는 돌아오고 비용을 돌려받는다.
        if let trip = scoutTrip, trip.region == .overseas, tier > .semiPro {
            let refund = trip.cost ?? scoutCost(.overseas)
            scoutTrip = nil
            funds.earn(refund, .recruit)
            post("해외 스카우트가 취소되어 ₩\(refund.formatted())을 돌려받았습니다.")
        }
        let limit = rosterLimit(tier)
        let count = teams[userTeamID].roster.count
        if count > limit {
            post("\(tier.displayName) 리그의 로스터 정원은 \(limit)명입니다. 지금 \(count)명이라 선수를 내보내기 전에는 새로 영입할 수 없습니다.")
        }

        // 강등 조항: 다른 구단이 정해진 이적료를 내고 데려간다. 거절할 수 없다.
        for player in roster(of: userTeamID) where player.contract.relegationClause && rng.chance(0.6) {
            let buyers = teams.filter { !$0.isUser && $0.tier < tier }
            guard !buyers.isEmpty else { continue }
            let buyer = rng.pick(buyers)
            let fee = Int(Double(Balance.transferValue(
                ability: player.ability, potential: player.potential, age: player.age)) * 0.8)
            add(player.id, to: buyer.id)
            funds.earn(fee, .sales)
            post("강등 조항 발동: \(player.name)이(가) \(buyer.name)(으)로 떠났습니다. 이적료 ₩\(fee.formatted()).")
        }
    }

    // MARK: 시상

    mutating func giveAwards() {
        awards.removeAll { $0.season < season - 1 }
        if sport == .football {
            giveFootballAwards()
            return
        }
        if sport == .basketball {
            giveBasketballAwards()
            return
        }
        for tier in LeagueTier.allCases {
            let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
            let batters = everyone.filter { !$0.isPitcher && $0.batting.plateAppearances >= 80 }
            let pitchers = everyone.filter { $0.isPitcher && $0.pitching.outs >= 90 }

            func record(_ title: String, _ player: Player?, _ detail: (Player) -> String) -> Player? {
                guard let player, let teamID = player.teamID else { return nil }
                awards.append(AwardRecord(
                    season: season, tier: tier, title: title, playerName: player.name,
                    teamName: teams[teamID].name, detail: detail(player),
                    isMine: isCareer ? isMyPlayer(player.id) : teamID == userTeamID))
                return player
            }

            let mvp = record("MVP", batters.max { ($0.batting.ops, $0.id) < ($1.batting.ops, $1.id) }) {
                "OPS \(String(format: "%.3f", $0.batting.ops))"
            }
            _ = record("타격왕", batters.max { ($0.batting.average, $0.id) < ($1.batting.average, $1.id) }) {
                "타율 \(String(format: "%.3f", $0.batting.average))"
            }
            _ = record("홈런왕", batters.max { ($0.batting.homeRuns, $0.id) < ($1.batting.homeRuns, $1.id) }) {
                "\($0.batting.homeRuns)홈런"
            }
            _ = record("다승왕", pitchers.max { ($0.pitching.wins, $0.id) < ($1.pitching.wins, $1.id) }) {
                "\($0.pitching.wins)승"
            }
            _ = record("평균자책점 1위", pitchers.min { ($0.pitching.era, $0.id) < ($1.pitching.era, $1.id) }) {
                "평균자책점 \(String(format: "%.2f", $0.pitching.era))"
            }
            _ = record("탈삼진왕", pitchers.max { ($0.pitching.strikeouts, $0.id) < ($1.pitching.strikeouts, $1.id) }) {
                "\($0.pitching.strikeouts)탈삼진"
            }

            // 각성: MVP는 잠재력이 조금 오른다.
            if let mvp, var player = players[mvp.id] {
                player.potential = min(99, player.potential + rng.double(3...8))
                players[player.id] = player
            }
        }
        // 선수 모드의 수상은 시즌 기록을 정리할 때 다룬다.
        let mine = isCareer ? [] : awards.filter { $0.season == season && $0.isMine }
        for award in mine {
            teams[userTeamID].fame += Balance.fameAward
            post("\(award.tier.displayName) \(award.title): \(award.playerName) (\(award.detail)). 인지도 +\(Int(Balance.fameAward)).")
        }
    }
}
