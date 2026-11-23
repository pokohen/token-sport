import Foundation

extension Game {
    // MARK: 다음 경기

    public struct NextMatch: Equatable, Sendable {
        public var kind: MatchKind
        public var opponent: TeamID
        public var userIsHome: Bool
        public var label: String
    }

    /// 다음에 치를 내 경기. 없으면 nil.
    public func nextMatch() -> NextMatch? {
        guard !isBankrupt else { return nil }
        // 선수 모드: 은퇴했거나 무소속이면 치를 경기가 없다.
        if let career, career.retired || career.isFreeAgent { return nil }
        switch phase {
        case .regular:
            // 컵 라운드를 치를 때가 됐으면 리그보다 먼저 치른다.
            if let tie = pendingCupTie, let cup {
                return NextMatch(
                    kind: .cup, opponent: tie.opponent(of: userTeamID), userIsHome: tie.home == userTeamID,
                    label: "컵대회 \(cup.roundName)")
            }
            guard round < roundsPerSeason,
                  let fixture = schedules[userTier.index][round].first(where: { $0.involves(userTeamID) })
            else { return nil }
            return NextMatch(
                kind: .regular, opponent: fixture.opponent(of: userTeamID),
                userIsHome: fixture.home == userTeamID,
                label: "\(round + 1)라운드")
        case .playoff:
            guard let mine = series.first(where: { !$0.isDecided && $0.involves(userTeamID) }) else { return nil }
            let home = mine.nextHome
            return NextMatch(
                kind: .playoff, opponent: home == userTeamID ? mine.nextAway : home,
                userIsHome: home == userTeamID,
                label: mine.nextLabel)
        case .offseason:
            guard friendliesPlayed < Balance.friendliesPerOffseason else { return nil }
            return NextMatch(
                kind: .friendly, opponent: friendlyOpponent(),
                userIsHome: friendliesPlayed % 2 == 0,
                label: "친선 경기 \(friendliesPlayed + 1)/\(Balance.friendliesPerOffseason)")
        }
    }

    /// 친선 상대: 다른 리그 팀. 시즌·경기 번호로 정해지므로 미리 볼 수 있다.
    func friendlyOpponent() -> TeamID {
        let mine = userTier.rawValue
        let tiers = LeagueTier.allCases.filter { $0.rawValue != mine && abs($0.rawValue - mine) <= 2 }
        var picker = SeededRNG(seed: UInt64(season) &* 1_000_003 &+ UInt64(friendliesPlayed) &* 97 &+ UInt64(userTeamID))
        let tier = picker.pick(tiers)
        return picker.pick(teams(in: tier)).id
    }

    func rules(for kind: MatchKind, tier: LeagueTier, home: TeamID) -> MatchRules {
        MatchRules(
            coldGame: tier.isCitizen && kind != .playoff && kind != .cup,
            maxInnings: kind == .playoff || kind == .cup ? nil : 11,
            homeEdge: Balance.stadiumHomeEdge[teams[home].stadiumLevel - 1])
    }

    func makeMatch(home: TeamID, away: TeamID, kind: MatchKind, tier: LeagueTier, seed: UInt64) -> MatchState? {
        guard let homeTeam = LineupBuilder.matchTeam(team: teams[home], players: players),
              let awayTeam = LineupBuilder.matchTeam(team: teams[away], players: players)
        else { return nil }
        return MatchState(
            away: awayTeam, home: homeTeam, rules: rules(for: kind, tier: tier, home: home), seed: seed)
    }

    // MARK: 경기 시작

    /// 경기 시작. 경기 기회를 하나 쓰고 실시간 중계를 연다.
    public mutating func startMatch(now: Date) throws {
        refreshCharges(now: now)
        guard !isBankrupt else { throw GameError("구단이 해체되었습니다. 새 구단을 만들어 주세요.") }
        guard !isMatchLive else { throw GameError("진행 중인 경기가 끝나야 다음 경기를 시작할 수 있습니다.") }
        guard charges > 0 else { throw GameError("아직 경기 기회가 없습니다.") }
        if let career {
            guard !career.retired else { throw GameError("은퇴했습니다. 새 선수를 만들어 주세요.") }
            guard !career.isFreeAgent else { throw GameError("무소속입니다. 입단할 구단을 먼저 골라 주세요.") }
        }
        guard let next = nextMatch() else { throw GameError("지금은 치를 경기가 없습니다.") }
        if isCareer {
            ensurePlayable(userTeamID)
            prepareCareerLineup(kind: next.kind)
        }
        guard canField(userTeam) else {
            switch sport {
            case .football: throw GameError("골키퍼 1명을 포함해 11명이 있어야 경기를 할 수 있습니다.")
            case .basketball: throw GameError("선수 다섯 명이 있어야 경기를 할 수 있습니다.")
            case .baseball: throw GameError("야수 9명과 투수 1명 이상이 있어야 경기를 할 수 있습니다.")
            }
        }

        ensurePlayable(next.opponent)
        let home = next.userIsHome ? userTeamID : next.opponent
        let away = next.userIsHome ? next.opponent : userTeamID
        let tier = next.kind == .friendly || next.kind == .cup ? min(userTier, teams[next.opponent].tier) : userTier
        // 친선 경기 규칙은 두 구단 중 윗 리그를 따른다 (콜드게임은 시민 구단끼리만).
        if sport == .football {
            try startFootballMatch(next, home: home, away: away, tier: tier, now: now)
            return
        }
        if sport == .basketball {
            try startBasketballMatch(next, home: home, away: away, tier: tier, now: now)
            return
        }
        guard var state = makeMatch(home: home, away: away, kind: next.kind, tier: tier, seed: rng.next()) else {
            throw GameError("경기를 시작할 수 없습니다.")
        }
        if isCareer { applyCareerForm(&state, userIsHome: next.userIsHome) }

        // 같은 라운드의 내 리그 다른 경기는 함께 돌아가며 "타 구장 소식"으로 보인다.
        var others: [MatchState] = []
        if next.kind == .regular {
            for fixture in schedules[userTier.index][round] where !fixture.involves(userTeamID) {
                ensurePlayable(fixture.home)
                ensurePlayable(fixture.away)
                if let other = makeMatch(
                    home: fixture.home, away: fixture.away, kind: .regular, tier: userTier, seed: rng.next()) {
                    others.append(other)
                }
            }
        }

        if charges >= Balance.maxMatchCharges { chargeAnchor = now }
        charges -= 1
        live = LiveMatch(kind: next.kind, state: state, others: others, userIsHome: next.userIsHome, tier: tier)
        lastResult = nil
    }

    /// 공 하나 진행. 내 경기가 끝나면 그 라운드의 나머지와 세계 시뮬레이션까지 처리한다.
    @discardableResult
    public mutating func stepMatch() -> [MatchEvent] {
        if liveFootball != nil { return stepFootballMatch() }
        if liveBasketball != nil { return stepBasketballMatch() }
        guard var match = live else { return [] }
        let events = match.state.step()
        for index in match.others.indices where !match.others[index].isFinished {
            match.others[index].step()
        }
        live = match
        if match.state.isFinished { finishLiveMatch() }
        return events
    }

    /// 화면 없이 끝까지 (테스트와 자동 진행용). 앱 화면에서는 부르지 않는다.
    public mutating func runMatchToEnd() {
        while isMatchLive { stepMatch() }
    }

    // MARK: 경기 끝

    mutating func finishLiveMatch() {
        guard var match = live else { return }
        live = nil
        playedFactor = [:]
        let state = match.state
        let userIsHome = match.userIsHome
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        var summary: [String] = []

        switch match.kind {
        case .regular:
            let tier = userTier
            apply(state, tier: tier, countsForStandings: true)
            for index in match.others.indices {
                match.others[index].runToEnd()
                apply(match.others[index], tier: tier, countsForStandings: true)
            }
            // 다른 다섯 리그의 같은 라운드
            for other in LeagueTier.allCases where other != tier {
                for fixture in schedules[other.index][round] {
                    ensurePlayable(fixture.home)
                    ensurePlayable(fixture.away)
                    guard var game = makeMatch(
                        home: fixture.home, away: fixture.away, kind: .regular, tier: other, seed: rng.next())
                    else { continue }
                    game.runToEnd()
                    apply(game, tier: other, countsForStandings: true)
                }
            }
            summary += settleUserMatch(
                kind: .regular, myScore: mine.runs, theirScore: theirs.runs, opponent: theirs.teamID, userIsHome: userIsHome)
            round += 1
        case .playoff:
            apply(state, tier: userTier, countsForStandings: false)
            if let index = series.firstIndex(where: { !$0.isDecided && $0.involves(userTeamID) }) {
                recordPlayoffGame(
                    index, home: state.home.teamID, homeScore: state.home.runs, awayScore: state.away.runs)
            }
            summary += settleUserMatch(
                kind: .playoff, myScore: mine.runs, theirScore: theirs.runs, opponent: theirs.teamID, userIsHome: userIsHome)
        case .friendly:
            apply(state, tier: userTier, countsForStandings: false)
            summary += settleUserMatch(
                kind: .friendly, myScore: mine.runs, theirScore: theirs.runs, opponent: theirs.teamID, userIsHome: userIsHome)
            friendliesPlayed += 1
        case .cup:
            apply(state, tier: userTier, countsForStandings: false)
            let roundName = cup?.roundName ?? ""
            recordCupTie(
                home: state.home.teamID, homeScore: state.home.runs, awayScore: state.away.runs,
                homeWon: state.home.runs > state.away.runs)
            summary += settleCareerCupTie(won: mine.runs > theirs.runs, opponent: theirs.teamID, roundName: roundName)
        }

        if isCareer { summary += settleCareerMatch(kind: match.kind, state: state, userIsHome: userIsHome) }

        lastResult = LastResult(
            kind: match.kind, myRuns: mine.runs, theirRuns: theirs.runs,
            opponent: theirs.name, wasHome: userIsHome, summary: summary)

        tick(kind: match.kind)
    }

    /// 경기 결과를 선수 기록·순위표에 반영한다.
    mutating func apply(_ state: MatchState, tier: LeagueTier, countsForStandings: Bool) {
        for (side, opponent) in [(state.home, state.away), (state.away, state.home)] {
            let teamID = side.teamID
            for batter in side.batters {
                guard var player = players[batter.playerID] else { continue }
                if countsForStandings { player.batting += batter.line }
                player.isHot = batter.line.hits >= 2 || batter.line.homeRuns >= 1
                players[player.id] = player
                playedFactor[player.id] = Balance.playFactorStarter * (player.isHot ? 1.1 : 1.0)
            }
            for (index, pitcher) in side.pitchers.enumerated() where pitcher.hasEntered {
                guard var player = players[pitcher.playerID] else { continue }
                if countsForStandings { player.pitching += pitcher.line }
                player.isHot = pitcher.line.outs >= 15 && pitcher.line.runs <= 2
                if index == 0 {
                    player.lastStartGame = teams[teamID].gamesPlayed
                } else {
                    let game = teams[teamID].gamesPlayed
                    player.reliefStreak = player.lastReliefGame == game - 1 ? (player.reliefStreak ?? 1) + 1 : 1
                    player.lastReliefGame = game
                    player.lastReliefPitches = pitcher.line.pitches
                }
                players[player.id] = player
                playedFactor[player.id] = index == 0 ? Balance.playFactorStarter : Balance.playFactorSub
            }
            teams[teamID].gamesPlayed += 1
            if teams[teamID].starterOverride == side.pitchers[0].playerID { teams[teamID].starterOverride = nil }

            guard countsForStandings,
                  let row = standings[tier.index].firstIndex(where: { $0.teamID == teamID })
            else { continue }
            var entry = standings[tier.index][row]
            entry.runsFor += side.runs
            entry.runsAgainst += opponent.runs
            entry.atBats += side.batters.reduce(0) { $0 + $1.line.atBats }
            entry.hits += side.hits
            entry.earnedRuns += side.pitchers.reduce(0) { $0 + $1.line.earnedRuns }
            entry.pitchingOuts += side.pitchers.reduce(0) { $0 + $1.line.outs }
            if side.runs > opponent.runs {
                entry.wins += 1
                entry.winsAgainst[opponent.teamID, default: 0] += 1
                teams[teamID].streak = max(1, teams[teamID].streak + 1)
            } else if side.runs < opponent.runs {
                entry.losses += 1
                teams[teamID].streak = min(-1, teams[teamID].streak - 1)
            } else {
                entry.draws += 1
            }
            standings[tier.index][row] = entry

            // CPU 구단 수입과 인지도
            if !teams[teamID].isUser {
                teams[teamID].funds += Balance.cpuIncomePerMatch(tier)
                teams[teamID].fame += side.runs > opponent.runs ? 1.5 : 0
            }
        }
    }

    /// 내 경기 정산: 인지도, 관중 수입, 스폰서, 연봉.
    /// `shootoutWon`: 승부차기로 끝난 축구 경기에서 내가 이겼는지.
    mutating func settleUserMatch(
        kind: MatchKind, myScore: Int, theirScore: Int, opponent: TeamID, userIsHome: Bool,
        shootoutWon: Bool? = nil
    ) -> [String] {
        // 선수 모드에는 구단 재정이 없다. 내 선수의 정산은 따로 한다.
        guard !isCareer else { return [] }
        var lines: [String] = []
        let tier = userTier
        let won = shootoutWon ?? (myScore > theirScore)
        let drew = shootoutWon == nil && myScore == theirScore
        var fameGain = 0.0

        switch kind {
        case .regular:
            if won {
                fameGain += Balance.fameWin
                if userTeam.streak >= 3 { fameGain += Balance.fameWinStreakBonus }
            } else if drew {
                fameGain += Balance.fameDraw
            } else if userTeam.streak <= -5 {
                fameGain -= Balance.fameLosingStreakPenalty
            }
        case .playoff:
            if won { fameGain += Balance.fameWin * 2 }
        case .friendly:
            if won, teams[opponent].tier < tier { fameGain += Balance.fameFriendlyUpset }
        case .cup:
            break
        }
        if fameGain != 0 {
            teams[userTeamID].fame = max(0, teams[userTeamID].fame + fameGain)
            lines.append("인지도 \(fameGain > 0 ? "+" : "")\(Int(fameGain))")
        }

        if userIsHome {
            let capacity = Balance.stadiumCapacity[userTeam.stadiumLevel - 1]
            let crowd = Int(Double(capacity) * Balance.attendanceRatio(fame: userTeam.fame, tier: tier))
            var gate = crowd * Balance.ticketPrice(tier)
            if kind == .friendly { gate /= 2 }
            funds.earn(gate, .gate)
            lines.append("관중 \(crowd.formatted())명, 수입 ₩\(gate.formatted())")
        }

        if kind == .regular {
            var sponsor = Int(userTeam.fame) * Balance.sponsorPerFame(tier)
            if sponsorPenaltySeasons > 0 { sponsor /= 2 }
            if sponsor > 0 {
                funds.earn(sponsor, .sponsor)
                lines.append("스폰서 ₩\(sponsor.formatted())")
            }
            let salary = salaryPerMatch
            funds.spend(salary, .salary)
            lines.append("연봉 지급 −₩\(salary.formatted())")
        }
        return lines
    }

    /// 경기를 치를 수 없는 CPU 구단이면 빈자리를 채운다.
    mutating func ensurePlayable(_ id: TeamID) {
        guard !teams[id].isUser else { return }
        func short() -> Bool {
            if sport != .baseball { return !canField(teams[id]) }
            return LineupBuilder.build(team: teams[id], players: players) == nil
                || roster(of: id).filter({ $0.isPitcher }).count < Balance.minPitchers
        }
        guard short() else { return }
        let target = strength(of: id)
        fillCPURoster(id, target: target)
        // 로스터가 꽉 차서 못 채웠으면 (윗 리그 인원을 그대로 들고 강등된 구단 등)
        // 정원을 넘는 포지션을 먼저 비우고 다시 채운다.
        guard short() else { return }
        trimCPURosterToShape(id)
        fillCPURoster(id, target: target)
    }
}
