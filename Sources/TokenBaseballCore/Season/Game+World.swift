import Foundation

/// 세계 시뮬레이션: 경기를 한 번 마칠 때마다 도는 틱.
extension Game {
    mutating func tick(kind: MatchKind) {
        // 1. 경기 진행은 이미 끝났다 (finishLiveMatch).
        // 2. 모든 선수 성장
        let before = myPlayer?.ability
        growAllPlayers(scale: kind == .friendly ? Balance.friendlyGrowthFactor : 1.0)
        // 선수 모드: 이번 경기로 내 선수가 얼마나 컸는지 경기 결과에 적는다.
        if let before, let after = myPlayer?.ability, after - before >= 0.005 {
            lastResult?.summary.append("이번 경기 성장: 능력 +\(String(format: "%.2f", after - before))")
            let peak = max(career?.peakAbility ?? 0, after)
            career?.peakAbility = peak
        }
        funds.trainingTokens = 0
        // 3. 컨디션은 경기 결과를 반영할 때 정했다.
        // 4. CPU 구단 운영
        if kind == .regular { runCPUClubs() }
        // 5. 맞춰주기는 성장 계산 안에서 한다.
        // 6. 이적 시장 소식
        if isCareer {
            resolveCareerMarketAfterMatch()
        } else {
            resolveMarketAfterMatch()
            updateFinancialState()
        }
        if isBankrupt, phase == .playoff {
            // 해체된 구단의 플레이오프는 상대의 부전승으로 끝낸다.
            for index in series.indices where !series[index].isDecided {
                if series[index].upperTeam == userTeamID { series[index].lowerWins = 2 } else { series[index].upperWins = 2 }
            }
        }

        // 시즌 흐름
        switch kind {
        case .regular:
            if !isCareer, round == Balance.applicationDeadlineRound, !expiryNoticeSent {
                expiryNoticeSent = true
                let leaving = roster(of: userTeamID).filter { isExpiring($0) }.map(\.name)
                if !leaving.isEmpty {
                    post("이번 시즌 후 계약이 끝나는 선수: \(leaving.joined(separator: ", ")). 재계약하지 않으면 떠납니다.")
                }
            }
            if isCareer {
                if round >= roundsPerSeason { finishCupQuietly() } else { openCupRoundIfDue() }
            }
            if round >= roundsPerSeason { endRegularSeason() }
        case .cup:
            finishCupRound()
        case .playoff:
            advancePlayoffs()
        case .friendly:
            if friendliesPlayed == Balance.draftAfterFriendly, !draftDone { runDraft() }
            if friendliesPlayed >= Balance.friendliesPerOffseason { endOffseason() }
        }
    }

    // MARK: 성장

    /// 맞춰주기: 이 CPU 팀의 성장 속도 배율.
    func rubberBandFactor(team: Team, userStrength: Double, leagueAverage: Double) -> Double {
        let range = Balance.strengthRange(team.tier)
        let current = strength(of: team.id)
        // 리그별 강도 범위는 어떤 설정에서도 지킨다.
        if current >= range.upperBound { return 0 }
        let band = effectiveRubberBand
        guard band != .off else { return 1 }

        let leagueTarget = clamp(userStrength, range.lowerBound, range.upperBound)
        let target = clamp(leagueTarget + team.targetOffset, range.lowerBound, range.upperBound)
        if current < target {
            // 한 시즌에 따라올 수 있는 양을 제한한다.
            let risen = leagueAverage - leagueStartAverage[team.tier.index]
            return risen >= band.seasonCap ? 1 : 1 + band.growthSwing
        }
        return 1 - band.growthSwing
    }

    mutating func growAllPlayers(scale: Double) {
        let userStrength = strength(of: userTeamID)
        let averages = LeagueTier.allCases.map { cpuAverageStrength($0) }
        // 토큰 연동 훈련: 지난 경기 이후 토큰을 많이 썼을수록 조금 더 큰다.
        let tokenBonus = 1 + min(0.25, log10(1 + Double(funds.trainingTokens) / 1_000_000) * 0.1)

        for index in teams.indices {
            let team = teams[index]
            var factor = Balance.trainingMultiplier[team.trainingLevel - 1] * scale
            if team.isUser {
                factor *= tokenBonus
            } else {
                factor *= rubberBandFactor(
                    team: team, userStrength: userStrength, leagueAverage: averages[team.tier.index])
            }
            for id in team.roster {
                guard var player = players[id] else { continue }
                let play = playedFactor[id] ?? Balance.playFactorBench
                // 선수 모드의 내 선수는 저절로는 조금만 크고, 나머지는 훈련으로 올린다.
                let mine = isMyPlayer(id) ? Balance.careerNaturalGrowth : 1
                Self.grow(&player, teamFactor: factor * mine, playFactor: play, focus: team.focus)
                players[id] = player
            }
        }
    }

    /// 성장 포인트 = 기본값 × 나이 계수 × 잠재력 여유 × 훈련 계수 × 출전 계수
    static func grow(_ player: inout Player, teamFactor: Double, playFactor: Double, focus: TrainingFocus) {
        let ability = player.ability
        guard player.potential > ability else { return }
        let room = (player.potential - ability) / player.potential
        var points = Balance.growthBase * Balance.ageGrowthFactor(player.age, position: player.position) * room * teamFactor * playFactor

        // 훈련 방침: 비중만큼 타자와 투수에게 경험치가 나뉜다.
        let normalized = focus.normalized
        let sport = player.position.sport
        let isFootball = sport != .baseball
        if isFootball {
            // 축구와 농구는 포지션별로 경험치를 나누지 않는다. 방침은 세부 능력치의 비중만 바꾼다.
        } else if player.isPitcher {
            points *= clamp(normalized.pitching / 0.25, 0.5, 2)
        } else {
            points *= clamp((1 - normalized.pitching) / 0.75, 0.5, 1.25)
        }
        points = min(points, player.potential - ability)
        guard points > 0 else { return }

        // 포지션 가중치와 방침에 따라 세부 능력치에 나눈다. 능력(CA)은 정확히 points만큼 오른다.
        let weights = Attributes.weights(for: player.position)
        let emphasis = weights.map {
            isFootball ? focus.emphasis(for: $0.0, sport: sport) : player.isPitcher ? 1.0 : focus.emphasis(for: $0.0)
        }
        let scale = zip(weights, emphasis).reduce(0) { $0 + $1.0.1 * $1.1 }
        guard scale > 0 else { return }
        for (index, (key, _)) in weights.enumerated() {
            player.attributes[key] = min(99, player.attributes[key] + points * emphasis[index] / scale)
        }
    }

    // MARK: CPU 구단 운영

    static let cpuFacilityCap = [10, 8, 6, 5, 4, 3]

    mutating func runCPUClubs() {
        for index in teams.indices where !teams[index].isUser {
            let tier = teams[index].tier
            let cap = Self.cpuFacilityCap[tier.index]
            // 자금이 모이면 훈련소 → 경기장 순으로 업그레이드한다.
            if teams[index].trainingLevel <= teams[index].stadiumLevel, teams[index].trainingLevel < cap {
                let cost = Balance.trainingCost[teams[index].trainingLevel - 1]
                if teams[index].funds >= cost {
                    teams[index].funds -= cost
                    teams[index].trainingLevel += 1
                    if tier == userTier || rng.chance(0.2) {
                        post("\(tier.displayName) \(teams[index].name), \(Balance.trainingNames(sport)[teams[index].trainingLevel - 1]) 완공")
                    }
                }
            } else if teams[index].stadiumLevel < cap {
                let cost = Balance.stadiumCost[teams[index].stadiumLevel - 1]
                if teams[index].funds >= cost {
                    teams[index].funds -= cost
                    teams[index].stadiumLevel += 1
                    teams[index].fame += Balance.stadiumFamePerLevel
                }
            }
        }

        // 눈에 띄는 유망주 소식
        if rng.chance(0.15) {
            let rivals = teams(in: userTier).filter { !$0.isUser }
            let team = rng.pick(rivals)
            let young = roster(of: team.id).filter { $0.age <= 22 && $0.potential - $0.ability > 8 }
            if let player = young.max(by: { ($0.potential, $0.id) < ($1.potential, $1.id) }) {
                let what = sport == .football ? "기량이 눈에 띄게 늘었습니다"
                    : player.isPitcher ? "구속이 눈에 띄게 올랐습니다" : "타격이 눈에 띄게 늘었습니다"
                post("\(team.name) \(player.age)세 \(player.position.label) \(player.name), \(what)")
            }
        }
    }

    // MARK: 로스터 정리 (CPU)

    /// 맞춰주기: 오프시즌 영입으로 맞출 리그 목표 평균. 끄기면 nil.
    /// 내 팀 강도를 리그 범위 안으로 자른 값을 향해, 시즌당 한도만큼만 움직인다.
    func leagueTargetAverage(_ tier: LeagueTier) -> Double? {
        let band = effectiveRubberBand
        guard band != .off else { return nil }
        let range = Balance.strengthRange(tier)
        let desired = clamp(strength(of: userTeamID), range.lowerBound, range.upperBound)
        let start = leagueStartAverage[tier.index]
        return clamp(desired, start - band.seasonCap, start + band.seasonCap)
    }

    /// CPU 팀 로스터 정리: 빈자리를 채우고, 넘치면 줄이고, 강도를 리그 범위와 맞춰주기 목표에 맞춘다.
    mutating func normalizeCPURoster(_ id: TeamID, leagueTarget: Double?) {
        guard !teams[id].isUser else { return }
        let tier = teams[id].tier
        let range = Balance.strengthRange(tier)
        let ability = Balance.abilityRange(tier)
        // 목표가 없으면 (맞춰주기 끄기) 지금 수준을 유지한다.
        let base = leagueTarget.map { $0 + teams[id].targetOffset } ?? strength(of: id)
        let target = clamp(base, range.lowerBound + 1, range.upperBound - 1)
        // 목표에서 이만큼 벗어나면 영입으로 맞춘다.
        let tolerance = leagueTarget == nil ? Double.infinity : 1.5
        let floor = max(range.lowerBound + 0.5, target - tolerance)
        let ceiling = min(range.upperBound - 0.5, target + tolerance)

        // 포지션별로 정원을 넘는 선수는 내보내고, 빈자리를 채운다.
        trimCPURosterToShape(id)
        fillCPURoster(id, target: target)

        // 강도가 범위나 목표를 벗어나면 주축 선수를 바꾼다.
        for _ in 0..<60 {
            let current = strength(of: id)
            // 선수 모드의 내 선수는 구단이 마음대로 내보내지 않는다.
            let core = coreRoster(id).filter { !isMyPlayer($0.id) }
            if current < floor, let weakest = core.min(by: { ($0.ability, $0.id) < ($1.ability, $1.id) }) {
                replace(weakest, in: id, ability: clamp(max(target, weakest.ability) + 4, ability.lowerBound, 99))
            } else if current > ceiling, let strongest = core.max(by: { ($0.ability, $0.id) < ($1.ability, $1.id) }) {
                replace(strongest, in: id, ability: clamp(min(target, strongest.ability) - 4, 1, ability.upperBound))
            } else {
                break
            }
        }
    }

    /// 지금 리그의 로스터 구성에서 포지션별 정원을 넘는 선수를 FA로 내보낸다 (능력이 낮은 고령 선수부터).
    /// 끝나면 로스터가 정원 이하가 되어 빈자리를 모두 채울 수 있다.
    mutating func trimCPURosterToShape(_ id: TeamID) {
        guard !teams[id].isUser else { return }
        let shape = rosterPositions(teams[id].tier)
        for position in Position.allCases {
            let quota = shape.filter { $0 == position }.count
            let same = roster(of: id).filter { $0.position == position }
                .sorted { ($0.ability - Double($0.age) * 0.3, -$0.id) > ($1.ability - Double($1.age) * 0.3, -$1.id) }
            for extra in same.dropFirst(quota) where !isMyPlayer(extra.id) { moveToFreeAgency(extra.id) }
        }
    }

    /// 팀 강도를 정하는 선수들: 야수 상위 9명과 선발 투수.
    func coreRoster(_ id: TeamID) -> [Player] {
        if sport == .football { return FootballLineupBuilder.core(team: teams[id], players: players) }
        if sport == .basketball { return BasketballLineupBuilder.core(team: teams[id], players: players) }
        let all = roster(of: id)
        let batters = all.filter { !$0.isPitcher }.sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }.prefix(9)
        return Array(batters) + all.filter { $0.position == .starter }
    }

    mutating func replace(_ old: Player, in id: TeamID, ability: Double) {
        var spec = PlayerFactory.Spec(position: old.position, tier: teams[id].tier, season: season)
        spec.ability = ability...ability
        spec.age = 22...30
        moveToFreeAgency(old.id)
        let player = makePlayer(spec)
        add(player.id, to: id)
    }
}
