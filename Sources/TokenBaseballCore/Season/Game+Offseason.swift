import Foundation

/// 오프시즌: 나이와 은퇴, 연봉과 계약, 드래프트, 새 시즌 준비.
extension Game {
    // MARK: 오프시즌

    mutating func startOffseason() {
        phase = .offseason
        friendliesPlayed = 0
        draftDone = false
        offers = []
        proposals = []
        counters = []

        // 나이 +1, 하락, 은퇴
        var retired: [String] = []
        for team in teams {
            for id in team.roster {
                guard var player = players[id] else { continue }
                player.age += 1
                if player.age >= Balance.declineStartAge(player.position) {
                    // 체력·주력부터 떨어진다.
                    for key in Attributes.Key.all(for: player.position.sport) {
                        let drop = key == .stamina || key == .speed ? rng.double(2.5...5) : rng.double(0.5...2)
                        player.attributes[key] = max(1, player.attributes[key] - drop)
                    }
                    player.potential = max(player.ability, player.potential - 2)
                } else if player.age >= Balance.earlyDeclineAge(player.position) {
                    // 본격적인 하락 전: 몸으로 하는 능력치만 조금 내려가고, 눈과 제구는 오히려 는다.
                    for key in Attributes.Key.all(for: player.position.sport) {
                        switch key {
                        case .speed, .stamina, .fielding, .stuff:
                            player.attributes[key] = max(1, player.attributes[key] - rng.double(0.5...1.5))
                        case .eye, .control:
                            player.attributes[key] = min(99, player.attributes[key] + rng.double(0...0.5))
                        default:
                            break
                        }
                    }
                }
                players[id] = player

                let start = Balance.retirementAge(team.tier, position: player.position)
                // 선수 모드의 내 선수는 스스로 은퇴를 정한다.
                if player.age >= start, !isMyPlayer(id), rng.chance(min(1, 0.12 * Double(player.age - start + 1))) {
                    if team.isUser { retired.append(player.name) }
                    removePlayer(id)
                }
            }
        }
        if !retired.isEmpty { post("은퇴: \(retired.joined(separator: ", "))") }

        // 연봉 인상 (내려가지 않는다)과 계약 기간 한 시즌 줄이기
        for team in teams {
            for id in team.roster {
                guard var player = players[id] else { continue }
                let improvement = max(0, player.ability - player.abilityAtSeasonStart)
                let performance = player.position.sport == .football
                    ? Self.footballPerformance(player) * 1.3
                    : player.position.sport == .basketball
                    ? Self.basketballPerformance(player)
                    : player.isPitcher
                    ? Double(player.pitching.wins + player.pitching.saves) / 15
                    : max(0, player.batting.ops - 0.7)
                let bonus = min(Balance.raiseMaxBonus, improvement * 0.02 + performance * 0.15)
                // 축구는 계약 기간 동안 연봉이 그대로다 (재계약할 때 오른다). 야구는 시즌마다 연봉 협상을 한다.
                if player.position.sport != .football {
                    player.contract.salary = Int(Double(player.contract.salary) * (1 + rng.double(Balance.raiseBase) + bonus))
                }
                player.contract.seasonsLeft -= 1
                players[id] = player
            }
        }

        // CPU 구단: 계약이 끝난 선수는 대부분 재계약하고, 나머지는 FA로 나온다.
        for team in teams where !team.isUser {
            for player in roster(of: team.id) where player.contract.seasonsLeft <= 0 && !isMyPlayer(player.id) {
                if rng.chance(0.75) {
                    players[player.id]?.contract.seasonsLeft = rng.int(1...3)
                } else {
                    moveToFreeAgency(player.id)
                }
            }
        }

        // FA 시장에 새 얼굴
        for tier in LeagueTier.allCases {
            for _ in 0..<6 {
                let positions = rosterPositions(tier)
                let player = makePlayer(PlayerFactory.Spec(position: rng.pick(positions), tier: tier, season: season))
                players[player.id]?.contract.seasonsLeft = 0
                freeAgents.append(player.id)
            }
        }

        // 인지도는 시즌이 바뀔 때 조금 줄고, 홍보 효과는 초기화된다.
        teams[userTeamID].fame *= 1 - Balance.fameSeasonDecay
        promotionUses = [:]

        // 맞춰주기: 강팀·약팀을 시즌마다 다시 정한다.
        for tier in LeagueTier.allCases {
            let offsets = rng.shuffled([8.0, 6, 4, 2, 0, -1, -3, -5, -7, -8])
            for (index, team) in teams(in: tier).filter({ !$0.isUser }).enumerated() {
                teams[team.id].targetOffset = offsets[index % offsets.count]
            }
        }

        let leaving = isCareer ? [] : roster(of: userTeamID).filter { isExpiring($0) }.map(\.name)
        post("오프시즌 시작. 친선 경기 \(Balance.friendliesPerOffseason)경기 동안 이적 시장이 열립니다.")
        if !leaving.isEmpty {
            post("계약 만료: \(leaving.joined(separator: ", ")). 오프시즌이 끝나기 전에 재계약하지 않으면 떠납니다.")
        }
        if relegatedThisOffseason { generateIncomingOffers(count: 3) }
        // 은퇴나 강등 조항으로 인원이 모자라면 친선 경기를 치를 수 있게 채운다.
        fillUserMinimumRoster()
        careerStartOffseason()
    }

    /// 축구에는 드래프트가 없다. 대신 오프시즌에 모든 구단이 자기 유소년 팀에서 선수를 올린다.
    /// 훈련소가 좋을수록 잠재력 높은 선수가 나온다. 내 구단은 후보 세 명 중 한 명을 고른다.
    mutating func runYouthIntake() {
        for team in teams {
            let tier = team.tier
            let range = Balance.abilityRange(tier)
            let academy = Double(team.trainingLevel)
            func youth() -> PlayerID {
                var spec = PlayerFactory.Spec(position: rng.pick(rosterPositions(tier)), tier: tier, season: season)
                spec.age = 16...18
                spec.ability = (range.lowerBound - 10)...(range.lowerBound + 2)
                spec.potential = (range.lowerBound + 4 + academy)...(range.upperBound + academy)
                return makePlayer(spec).id
            }
            if team.isUser {
                let board = (0..<3).map { _ in youth() }
                candidates += board.map {
                    Candidate(id: newMarketID(), playerID: $0, fee: 0, matchesLeft: 99, source: .draft)
                }
                post("유소년 승급: 유소년 팀에서 후보 \(board.count)명이 올라왔습니다. 선수 탭에서 한 명을 고르세요.")
            } else if teams[team.id].roster.count < rosterLimit(tier) {
                add(youth(), to: team.id)
            }
        }
    }

    /// 신인 드래프트 (3부 이상): 지난 시즌 순위 역순으로 지명한다.
    mutating func runDraft() {
        draftDone = true
        if sport == .football {
            runYouthIntake()
            return
        }
        for tier in [LeagueTier.pro, .semiPro, .amateur] {
            let range = Balance.abilityRange(tier)
            var pool: [PlayerID] = []
            for _ in 0..<14 {
                var spec = PlayerFactory.Spec(
                    position: rng.pick(rosterPositions(tier)), tier: tier, season: season)
                spec.age = 18...22
                spec.ability = (range.lowerBound - 8)...(range.lowerBound + 6)
                spec.potential = (range.lowerBound + 8)...(range.upperBound + 5)
                pool.append(makePlayer(spec).id)
            }
            func value(_ id: PlayerID) -> Double {
                guard let player = players[id] else { return 0 }
                return player.potential * 0.6 + player.ability * 0.4
            }
            pool.sort { (value($0), -$0) > (value($1), -$1) }

            let order = teams(in: tier).sorted {
                (lastWinRate[$0.id] ?? 0, $0.id) < (lastWinRate[$1.id] ?? 0, $1.id)
            }
            for team in order {
                guard !pool.isEmpty else { break }
                if team.isUser {
                    // 내 차례: 남은 선수 중 다섯 명이 지명 후보로 온다. 한 명만 고를 수 있다.
                    let board = pool.prefix(5)
                    candidates += board.map {
                        Candidate(id: newMarketID(), playerID: $0, fee: 0, matchesLeft: 99, source: .draft)
                    }
                    pool.removeFirst(board.count)
                    post("신인 드래프트: 지명 후보 \(board.count)명이 왔습니다. 선수 탭에서 한 명을 고르세요.")
                } else if teams[team.id].roster.count < rosterLimit(tier) {
                    add(pool.removeFirst(), to: team.id)
                }
            }
            pool.forEach { removePlayer($0) }
        }
    }

    mutating func endOffseason() {
        // 선수 모드: 계약이 없는 내 선수는 여기서 무소속이 된다 (아래의 구단 모드 정리에 걸리지 않게 먼저 한다).
        careerEndOffseason()
        // 재계약하지 않은 계약 만료 선수는 떠난다.
        // 역제안에 아직 답하지 않은 선수는 다음 경기가 끝날 때까지 기다려 준다
        // (마지막 친선 경기 뒤에 온 역제안은 답할 틈이 없기 때문이다).
        counters.removeAll { players[$0.playerID]?.teamID != userTeamID }
        let waiting = Set(counters.map(\.playerID))
        let expired = roster(of: userTeamID).filter { $0.contract.seasonsLeft <= 0 }
        let leaving = expired.filter { !waiting.contains($0.id) }
        for player in leaving { moveToFreeAgency(player.id) }
        if !leaving.isEmpty {
            post("계약이 끝나 떠난 선수: \(leaving.map(\.name).joined(separator: ", "))")
        }
        let staying = expired.filter { waiting.contains($0.id) }
        if !staying.isEmpty {
            post("재계약 역제안에 답하지 않은 선수: \(staying.map(\.name).joined(separator: ", ")). 다음 경기가 끝날 때까지 답하지 않으면 떠납니다.")
        }

        // 남은 후보·제안 정리. 드래프트 지명권은 사라지고, 스카우트 후보와 출장은 새 시즌으로 이어진다.
        for candidate in candidates where candidate.source == .draft { removePlayer(candidate.playerID) }
        candidates.removeAll { $0.source == .draft }
        offers = []
        proposals = []

        // CPU 구단: FA에서 약한 자리를 채우고, 로스터를 리그에 맞게 정리한다.
        let targets = LeagueTier.allCases.map { leagueTargetAverage($0) }
        for team in teams where !team.isUser {
            signFreeAgentForCPU(team.id)
            normalizeCPURoster(team.id, leagueTarget: targets[team.tier.index])
        }
        fillUserMinimumRoster()
        trimFreeAgents()

        // 새 시즌
        season += 1
        round = 0
        phase = .regular
        appliedForPromotion = false
        expiryNoticeSent = false
        relegatedThisOffseason = false
        funds.startNewSeason()
        for team in teams {
            teams[team.id].streak = 0
            for id in team.roster {
                guard var player = players[id] else { continue }
                player.batting = BattingLine()
                player.pitching = PitchingLine()
                if player.position.sport == .football { player.football = FootballLine() }
                if player.position.sport == .basketball { player.basketball = BasketballLine() }
                player.suspendedMatches = nil
                player.abilityAtSeasonStart = player.ability
                player.isHot = false
                players[id] = player
            }
        }
        expandLeaguesIfNeeded()
        startSeasonSchedules()
        post("\(season)번째 시즌 시작! \(userTier.displayName) 리그.")
        careerStartSeason()
    }

    /// CPU 구단이 FA 시장에서 가장 약한 자리를 한 명 보강한다.
    mutating func signFreeAgentForCPU(_ id: TeamID) {
        let tier = teams[id].tier
        let range = Balance.abilityRange(tier)
        guard teams[id].roster.count < rosterLimit(tier),
              let weakest = coreRoster(id).min(by: { ($0.ability, $0.id) < ($1.ability, $1.id) })
        else { return }
        let options = freeAgents.compactMap { players[$0] }.filter {
            $0.position == weakest.position && $0.ability > weakest.ability + 2
                && range.contains($0.ability) && $0.age < Balance.retirementAge(tier)
        }
        guard let pick = options.max(by: { ($0.ability, $0.id) < ($1.ability, $1.id) }) else { return }
        add(pick.id, to: id)
        players[pick.id]?.contract = Contract(
            salary: Balance.marketSalary(ability: pick.ability), seasonsLeft: rng.int(1...3))
    }

    /// 내 팀에 경기를 치를 최소 인원이 없으면 임시 선수를 데려온다.
    mutating func fillUserMinimumRoster() {
        // 선수 모드의 내 구단은 CPU 구단이라 CPU 방식으로 채운다.
        guard !isCareer else { return }
        if sport == .football {
            fillUserMinimumSquad()
            return
        }
        var added: [String] = []
        func count(_ pitcher: Bool) -> Int { roster(of: userTeamID).filter { $0.isPitcher == pitcher }.count }
        while count(false) < Balance.minBatters || count(true) < Balance.minPitchers {
            let needPitcher = count(true) < Balance.minPitchers
            let have = Set(roster(of: userTeamID).map(\.position))
            let position: Position = needPitcher
                ? (have.contains(.starter) ? .reliever : .starter)
                : (Position.fieldPositions.first { !have.contains($0) } ?? .designated)
            var spec = PlayerFactory.Spec(position: position, tier: userTier, season: season)
            let low = Balance.abilityRange(userTier).lowerBound
            spec.ability = low...(low + 5)
            let player = makePlayer(spec)
            players[player.id]?.contract.seasonsLeft = 1
            add(player.id, to: userTeamID)
            added.append(player.name)
        }
        if !added.isEmpty {
            post("선수가 모자라 임시 선수를 데려왔습니다: \(added.joined(separator: ", "))")
        }
    }

    mutating func trimFreeAgents() {
        let limit = 120
        guard freeAgents.count > limit else { return }
        let sorted = freeAgents.compactMap { players[$0] }
            .sorted { ($0.ability - Double($0.age), $0.id) > ($1.ability - Double($1.age), $1.id) }
        for player in sorted.dropFirst(limit) { removePlayer(player.id) }
    }
}
