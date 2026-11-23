import Foundation

/// 축구 모드에서만 쓰는 부분: 경기 시작·진행·정산, 시상, 기록 순위, 최소 인원.
/// 시즌 흐름·재정·이적 시장은 야구와 같은 코드를 쓴다.
extension Game {
    // MARK: 경기 만들기

    func footballRules(for kind: MatchKind, home: TeamID) -> FootballRules {
        FootballRules(
            mustHaveWinner: kind == .playoff || kind == .cup,
            homeEdge: Balance.stadiumHomeEdge[teams[home].stadiumLevel - 1])
    }

    /// 이 구단이 다음 경기에 쓸 포메이션. 내 구단은 고른 것, CPU 구단은 선수 구성에 맞는 것.
    public func formation(of id: TeamID) -> Formation {
        let team = teams[id]
        if let chosen = team.formation { return chosen }
        if team.isUser { return .f442 }
        return FootballLineupBuilder.fitted(team: team, players: players, season: season)
    }

    func makeFootballMatch(
        home: TeamID, away: TeamID, kind: MatchKind, seed: UInt64, rules: FootballRules? = nil
    ) -> FootballMatch? {
        var homeTeam = teams[home], awayTeam = teams[away]
        homeTeam.formation = formation(of: home)
        awayTeam.formation = formation(of: away)
        let friendly = kind == .friendly
        guard let homeSide = FootballLineupBuilder.side(team: homeTeam, players: players, ignoreSuspensions: friendly),
              let awaySide = FootballLineupBuilder.side(team: awayTeam, players: players, ignoreSuspensions: friendly)
        else { return nil }
        return FootballMatch(
            away: awaySide, home: homeSide, rules: rules ?? footballRules(for: kind, home: home), seed: seed)
    }

    /// 화면 없이 치른 경기의 결과.
    struct QuietResult {
        var homeScore: Int
        var awayScore: Int
        var homeWon: Bool
        /// 축구: 승부차기로 갈렸는지.
        var shootout: Bool
    }

    /// 순위표에 들어가지 않는 경기(승강 플레이오프, 컵대회)를 화면 없이 끝까지 치르고 선수 기록에 반영한다.
    /// 종목에 맞는 엔진을 쓴다. 경기를 만들 수 없으면(선수가 모자란 구단) nil.
    mutating func playQuietKnockout(
        home: TeamID, away: TeamID, kind: MatchKind, tier: LeagueTier, seed: UInt64,
        footballRules: FootballRules? = nil
    ) -> QuietResult? {
        if sport == .football {
            guard var match = makeFootballMatch(home: home, away: away, kind: kind, seed: seed, rules: footballRules)
            else { return nil }
            match.runToEnd()
            applyFootball(match, tier: tier, countsForStandings: false, competitive: true)
            return QuietResult(
                homeScore: match.home.goals, awayScore: match.away.goals,
                homeWon: match.result == .homeWin, shootout: match.wentToShootout)
        }
        if sport == .basketball {
            guard var match = makeBasketballMatch(home: home, away: away, seed: seed) else { return nil }
            match.runToEnd()
            applyBasketball(match, tier: tier, countsForStandings: false)
            return QuietResult(
                homeScore: match.home.points, awayScore: match.away.points,
                homeWon: match.result == .homeWin, shootout: false)
        }
        guard var match = makeMatch(home: home, away: away, kind: kind, tier: tier, seed: seed) else { return nil }
        match.runToEnd()
        // 기록에는 넣지 않지만 선발 등판은 남겨서 같은 투수가 연달아 나오지 않게 한다.
        apply(match, tier: tier, countsForStandings: false)
        return QuietResult(
            homeScore: match.home.runs, awayScore: match.away.runs,
            homeWon: match.home.runs > match.away.runs, shootout: false)
    }

    /// 화면 없이 한 경기를 끝까지 치르고 홈 팀이 이겼는지 돌려준다 (승부가 나야 하는 경기용).
    /// 경기를 만들 수 없으면 nil.
    mutating func homeWinsCPUMatch(home: TeamID, away: TeamID, kind: MatchKind, tier: LeagueTier) -> Bool? {
        let seed = rng.next()
        if sport == .football {
            guard var match = makeFootballMatch(home: home, away: away, kind: kind, seed: seed) else { return nil }
            match.runToEnd()
            return match.result == .homeWin
        }
        if sport == .basketball {
            guard var match = makeBasketballMatch(home: home, away: away, seed: seed) else { return nil }
            match.runToEnd()
            return match.result == .homeWin
        }
        guard var game = makeMatch(home: home, away: away, kind: kind, tier: tier, seed: seed) else { return nil }
        game.runToEnd()
        return game.home.runs > game.away.runs
    }

    // MARK: 경기 시작과 진행

    mutating func startFootballMatch(
        _ next: NextMatch, home: TeamID, away: TeamID, tier: LeagueTier, now: Date
    ) throws {
        // 플레이오프는 대진 형식에 따라 규칙이 다르다 (합산 2차전, 중립 결승).
        let playoffRules = next.kind == .playoff
            ? series.first { !$0.isDecided && $0.involves(userTeamID) }.map { footballPlayoffRules($0, home: home) }
            : nil
        guard var state = makeFootballMatch(
            home: home, away: away, kind: next.kind, seed: rng.next(), rules: playoffRules)
        else {
            throw GameError("경기를 시작할 수 없습니다.")
        }
        if isCareer {
            decorateCareerFootball(&state, userIsHome: next.userIsHome)
            applyCareerForm(&state, userIsHome: next.userIsHome)
        }
        // 같은 라운드의 내 리그 다른 경기는 함께 돌아가며 "타 구장 소식"으로 보인다.
        var others: [FootballMatch] = []
        if next.kind == .regular {
            for fixture in schedules[userTier.index][round] where !fixture.involves(userTeamID) {
                ensurePlayable(fixture.home)
                ensurePlayable(fixture.away)
                if let other = makeFootballMatch(
                    home: fixture.home, away: fixture.away, kind: .regular, seed: rng.next()) {
                    others.append(other)
                }
            }
        }
        if charges >= Balance.maxMatchCharges { chargeAnchor = now }
        charges -= 1
        liveFootball = LiveFootballMatch(
            kind: next.kind, state: state, others: others, userIsHome: next.userIsHome, tier: tier)
        lastResult = nil
    }

    mutating func stepFootballMatch() -> [MatchEvent] {
        guard var match = liveFootball else { return [] }
        let events = match.state.step()
        for index in match.others.indices where !match.others[index].isFinished {
            match.others[index].step()
        }
        liveFootball = match
        if match.state.isFinished { finishLiveFootballMatch() }
        return events
    }

    // MARK: 경기 끝

    mutating func finishLiveFootballMatch() {
        guard var match = liveFootball else { return }
        liveFootball = nil
        playedFactor = [:]
        let state = match.state
        let userIsHome = match.userIsHome
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        let userWon = state.result == (userIsHome ? .homeWin : .awayWin)
        let shootoutWon: Bool? = state.wentToShootout ? userWon : nil
        var summary: [String] = []

        func settle(_ kind: MatchKind) -> [String] {
            settleUserMatch(
                kind: kind, myScore: mine.goals, theirScore: theirs.goals, opponent: theirs.teamID,
                userIsHome: userIsHome, shootoutWon: shootoutWon)
        }

        switch match.kind {
        case .regular:
            let tier = userTier
            applyFootball(state, tier: tier, countsForStandings: true)
            for index in match.others.indices {
                match.others[index].runToEnd()
                applyFootball(match.others[index], tier: tier, countsForStandings: true)
            }
            // 다른 다섯 리그의 같은 라운드
            for other in LeagueTier.allCases where other != tier {
                for fixture in schedules[other.index][round] {
                    ensurePlayable(fixture.home)
                    ensurePlayable(fixture.away)
                    guard var game = makeFootballMatch(
                        home: fixture.home, away: fixture.away, kind: .regular, seed: rng.next())
                    else { continue }
                    game.runToEnd()
                    applyFootball(game, tier: other, countsForStandings: true)
                }
            }
            summary += settle(.regular)
            round += 1
        case .playoff:
            applyFootball(state, tier: userTier, countsForStandings: false, competitive: true)
            if let index = series.firstIndex(where: { !$0.isDecided && $0.involves(userTeamID) }) {
                recordPlayoffGame(
                    index, home: state.home.teamID, homeScore: state.home.goals, awayScore: state.away.goals,
                    shootoutHomeWon: state.wentToShootout ? state.result == .homeWin : nil)
            }
            summary += settle(.playoff)
        case .friendly:
            applyFootball(state, tier: userTier, countsForStandings: false)
            summary += settle(.friendly)
            friendliesPlayed += 1
        case .cup:
            applyFootball(state, tier: userTier, countsForStandings: false, competitive: true)
            let roundName = cup?.roundName ?? ""
            recordCupTie(
                home: state.home.teamID, homeScore: state.home.goals, awayScore: state.away.goals,
                homeWon: state.result == .homeWin, shootout: state.wentToShootout)
            summary += settleCareerCupTie(won: userWon, opponent: theirs.teamID, roundName: roundName)
        }

        if isCareer { summary += settleCareerFootballMatch(kind: match.kind, state: state, userIsHome: userIsHome) }

        lastResult = LastResult(
            kind: match.kind, myRuns: mine.goals, theirRuns: theirs.goals,
            opponent: theirs.name, wasHome: userIsHome, summary: summary, shootoutWon: shootoutWon)

        tick(kind: match.kind)
    }

    /// 경기 결과를 선수 기록·순위표에 반영한다.
    /// `competitive`: 출장 정지를 채우는 경기인지 (리그 경기와 플레이오프). 친선 경기는 아니다.
    mutating func applyFootball(
        _ state: FootballMatch, tier: LeagueTier, countsForStandings: Bool, competitive: Bool? = nil
    ) {
        for (side, opponent) in [(state.home, state.away), (state.away, state.home)] {
            let teamID = side.teamID
            if competitive ?? countsForStandings {
                // 이 경기를 쉬며 출장 정지를 채운 선수들.
                for id in teams[teamID].roster {
                    if let left = players[id]?.suspendedMatches, left > 0 {
                        players[id]?.suspendedMatches = left > 1 ? left - 1 : nil
                    }
                }
            }
            for (index, entry) in side.players.enumerated() where entry.hasPlayed {
                guard var player = players[entry.playerID] else { continue }
                if countsForStandings {
                    var line = player.football ?? FootballLine()
                    let yellowsBefore = line.yellowCards
                    line += entry.line
                    player.football = line
                    // 출장 정지: 퇴장은 다음 리그 한 경기, 시즌 경고 다섯 장마다 한 경기.
                    if entry.line.redCards > 0 {
                        player.suspendedMatches = Balance.footballRedCardBan
                    } else if line.yellowCards / Balance.footballYellowsPerBan > yellowsBefore / Balance.footballYellowsPerBan {
                        player.suspendedMatches = 1
                    }
                }
                player.isHot = entry.line.goals >= 1 || entry.line.assists >= 2
                    || (entry.line.cleanSheets >= 1 && entry.line.saves >= 3)
                players[player.id] = player
                let started = index < Balance.footballStarters
                playedFactor[player.id] = started
                    ? Balance.playFactorStarter * (player.isHot ? 1.1 : 1.0) : Balance.playFactorSub
            }
            teams[teamID].gamesPlayed += 1

            guard countsForStandings,
                  let row = standings[tier.index].firstIndex(where: { $0.teamID == teamID })
            else { continue }
            var entry = standings[tier.index][row]
            entry.runsFor += side.goals
            entry.runsAgainst += opponent.goals
            if side.goals > opponent.goals {
                entry.wins += 1
                entry.winsAgainst[opponent.teamID, default: 0] += 1
                teams[teamID].streak = max(1, teams[teamID].streak + 1)
            } else if side.goals < opponent.goals {
                entry.losses += 1
                teams[teamID].streak = min(-1, teams[teamID].streak - 1)
            } else {
                entry.draws += 1
            }
            standings[tier.index][row] = entry

            // CPU 구단 수입과 인지도
            if !teams[teamID].isUser {
                teams[teamID].funds += Balance.cpuIncomePerMatch(tier)
                teams[teamID].fame += side.goals > opponent.goals ? 1.5 : 0
            }
        }
    }

    // MARK: 인원

    /// 이 선수를 내보내도 경기를 치를 인원이 남는지.
    func canSpare(_ id: PlayerID) -> Bool {
        let mates = roster(of: userTeamID).filter { $0.id != id }
        if sport == .football {
            return mates.count >= Balance.footballStarters && mates.contains { $0.position == .goalkeeper }
        }
        return mates.filter { !$0.isPitcher }.count >= Balance.minBatters
            && mates.filter { $0.isPitcher }.count >= Balance.minPitchers
    }

    /// 축구: 내 팀이 최소 인원(14명, 골키퍼 1명 이상)에 못 미치면 임시 선수를 데려온다.
    mutating func fillUserMinimumSquad() {
        var added: [String] = []
        let shape = rosterPositions(userTier)
        while true {
            let squad = roster(of: userTeamID)
            let needKeeper = !squad.contains { $0.position == .goalkeeper }
            guard needKeeper || squad.count < Balance.footballMinSquad else { break }
            // 정원 대비 가장 모자란 포지션부터 채운다.
            let position: Position = needKeeper ? .goalkeeper : Position.football.max { a, b in
                func gap(_ p: Position) -> Int { shape.filter { $0 == p }.count - squad.filter { $0.position == p }.count }
                return gap(a) < gap(b)
            } ?? .midfielder
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

    // MARK: 성적

    /// 연봉 협상에 쓰는 시즌 활약도 (0 ~ 대략 1).
    static func footballPerformance(_ player: Player) -> Double {
        let line = player.football ?? FootballLine()
        if player.position == .goalkeeper { return Double(line.cleanSheets) / 30 }
        return (Double(line.goals) + Double(line.assists) * 0.6) / 40
    }

    mutating func giveFootballAwards() {
        for tier in LeagueTier.allCases {
            let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
            let regulars = everyone.filter { ($0.football?.games ?? 0) >= roundsPerSeason / 2 }
            let keepers = regulars.filter { $0.position == .goalkeeper }
            let outfield = regulars.filter { $0.position != .goalkeeper }
            func line(_ player: Player) -> FootballLine { player.football ?? FootballLine() }

            func record(_ title: String, _ player: Player?, _ detail: (Player) -> String) -> Player? {
                guard let player, let teamID = player.teamID else { return nil }
                awards.append(AwardRecord(
                    season: season, tier: tier, title: title, playerName: player.name,
                    teamName: teams[teamID].name, detail: detail(player),
                    isMine: isCareer ? isMyPlayer(player.id) : teamID == userTeamID))
                return player
            }
            func value(_ player: Player) -> Double { Double(line(player).goals) + Double(line(player).assists) * 0.7 }

            let mvp = record("MVP", outfield.max { (value($0), $0.id) < (value($1), $1.id) }) {
                "\(line($0).goals)골 \(line($0).assists)도움"
            }
            _ = record("득점왕", outfield.max { (line($0).goals, $0.id) < (line($1).goals, $1.id) }) {
                "\(line($0).goals)골"
            }
            _ = record("도움왕", outfield.max { (line($0).assists, $0.id) < (line($1).assists, $1.id) }) {
                "\(line($0).assists)도움"
            }
            _ = record("최우수 골키퍼", keepers.max {
                (line($0).cleanSheets, -line($0).conceded, $0.id) < (line($1).cleanSheets, -line($1).conceded, $1.id)
            }) {
                "무실점 \(line($0).cleanSheets)경기"
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

    func footballLeaders(_ tier: LeagueTier, count: Int) -> [(title: String, rows: [Leader])] {
        let everyone = teams(in: tier).flatMap { roster(of: $0.id) }.filter { ($0.football?.games ?? 0) > 0 }
        func line(_ player: Player) -> FootballLine { player.football ?? FootballLine() }
        func rows(_ list: [Player], _ text: (Player) -> String) -> [Leader] {
            list.prefix(count).map {
                Leader(
                    playerName: $0.name, teamName: $0.teamID.map { teams[$0].name } ?? "",
                    value: text($0), isMine: isCareer ? isMyPlayer($0.id) : $0.teamID == userTeamID)
            }
        }
        let keepers = everyone.filter { $0.position == .goalkeeper && line($0).games >= max(1, round / 2) }
        return [
            ("득점", rows(everyone.sorted { (line($0).goals, -$0.id) > (line($1).goals, -$1.id) }) { "\(line($0).goals)" }),
            ("도움", rows(everyone.sorted { (line($0).assists, -$0.id) > (line($1).assists, -$1.id) }) { "\(line($0).assists)" }),
            ("공격 포인트", rows(everyone.sorted { (line($0).points, -$0.id) > (line($1).points, -$1.id) }) { "\(line($0).points)" }),
            ("슈팅", rows(everyone.sorted { (line($0).shots, -$0.id) > (line($1).shots, -$1.id) }) { "\(line($0).shots)" }),
            ("무실점 경기", rows(keepers.sorted { (line($0).cleanSheets, -$0.id) > (line($1).cleanSheets, -$1.id) }) {
                "\(line($0).cleanSheets)"
            }),
            ("선방", rows(keepers.sorted { (line($0).saves, -$0.id) > (line($1).saves, -$1.id) }) { "\(line($0).saves)" }),
        ]
    }
}
