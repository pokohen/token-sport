import Foundation

/// e스포츠 1:1 대전에서만 쓰는 부분: 출전 순서, 경기 시작·진행·정산, 화면 없이 치르는 경기.
/// 내 선수의 평점과 팬은 `Career/Game+CareerDuel.swift`. 시즌 흐름, 승강(야구 방식), 계약과 이적은 다른 종목과 같은 코드를 쓴다.
extension Game {
    // MARK: 출전 순서

    /// 팀 경기에 나서는 선수: 3전 2선승이면 두 명, 5전 3선승이면 네 명. 맨 앞이 에이스다 (1세트와 에이스 결정전).
    /// 능력에 그날의 기세를 더해 세운다. 선수 모드의 내 선수가 그 안에 들지 못해도 몇 경기에 한 번은 마지막 일반 세트를 받는다.
    func duelLineup(_ team: TeamID, bestOf: Int) -> [PlayerID]? {
        guard let order = DuelLineupBuilder.build(team: teams[team], players: players) else { return nil }
        let ranked = order.compactMap { players[$0] }
            .sorted { ($0.ability + ($0.isHot ? 2 : 0), -$0.id) > ($1.ability + ($1.isHot ? 2 : 0), -$1.id) }
            .map(\.id)
        var lineup = Array(ranked.prefix(max(1, bestOf - 1)))
        if let career, !career.retired, let me = players[career.playerID], me.teamID == team,
           !lineup.contains(me.id), lineup.count > 1,
           teams[team].gamesPlayed - me.lastStartGame >= Balance.careerDuelGuaranteedEvery {
            lineup[lineup.count - 1] = me.id
        }
        return lineup
    }

    /// 세트에 나갈 선수의 모습. 선수 모드의 내 선수에게는 고른 스타일과 그날의 컨디션을 붙인다.
    func duelPlayer(_ id: PlayerID) -> DuelPlayer? {
        guard let player = players[id] else { return nil }
        guard let career, career.playerID == id else { return DuelPlayer(player) }
        var duel = DuelPlayer(player, style: career.duelStyle ?? .balanced)
        let factor = 1 + careerFormModifier
        if factor != 1 {
            for key in DuelSkills.keys { duel.skills[keyPath: key] = clamp(duel.skills[keyPath: key] * factor, 1, 99) }
        }
        return duel
    }

    func duelSide(_ team: TeamID, bestOf: Int) -> DuelMatch.Side? {
        guard let lineup = duelLineup(team, bestOf: bestOf) else { return nil }
        var roster: [PlayerID: DuelPlayer] = [:]
        for id in lineup { roster[id] = duelPlayer(id) }
        return DuelMatch.Side(teamID: team, name: teams[team].name, lineup: lineup, players: roster)
    }

    /// 팀 경기. 정규 시즌은 3전 2선승, 승강 플레이오프는 5전 3선승이다.
    func makeDuelMatch(home: TeamID, away: TeamID, kind: MatchKind, seed: UInt64) -> DuelMatch? {
        let bestOf = kind == .playoff ? 5 : DuelLineupBuilder.setsPerMatch
        guard let homeSide = duelSide(home, bestOf: bestOf), let awaySide = duelSide(away, bestOf: bestOf) else { return nil }
        return DuelMatch(home: homeSide, away: awaySide, bestOf: bestOf, seed: seed)
    }

    // MARK: 경기 시작과 진행

    mutating func startDuelMatch(_ next: NextMatch, home: TeamID, away: TeamID, tier: LeagueTier, now: Date) throws {
        guard let state = makeDuelMatch(home: home, away: away, kind: next.kind, seed: rng.next()) else {
            throw GameError("경기를 시작할 수 없습니다.")
        }
        // 같은 라운드의 내 리그 다른 경기는 함께 돌아가며 "타 구장 소식"으로 보인다.
        var others: [DuelMatch] = []
        if next.kind == .regular {
            for fixture in schedules[userTier.index][round] where !fixture.involves(userTeamID) {
                ensurePlayable(fixture.home)
                ensurePlayable(fixture.away)
                if let other = makeDuelMatch(home: fixture.home, away: fixture.away, kind: .regular, seed: rng.next()) {
                    others.append(other)
                }
            }
        }
        if charges >= Balance.maxMatchCharges { chargeAnchor = now }
        charges -= 1
        liveDuel = LiveDuelMatch(kind: next.kind, state: state, others: others, userIsHome: next.userIsHome, tier: tier)
        lastResult = nil
    }

    mutating func stepDuelMatch() -> [MatchEvent] {
        guard var match = liveDuel else { return [] }
        let events = match.state.step()
        for index in match.others.indices where !match.others[index].isFinished {
            match.others[index].step()
        }
        liveDuel = match
        if match.state.isFinished { finishLiveDuel() }
        return events
    }

    // MARK: 경기 끝

    mutating func finishLiveDuel() {
        guard var match = liveDuel else { return }
        liveDuel = nil
        playedFactor = [:]
        let state = match.state
        let userIsHome = match.userIsHome
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        let opponent = theirs.teamID ?? userTeamID
        var summary: [String] = []

        func settle(_ kind: MatchKind) -> [String] {
            settleUserMatch(kind: kind, myScore: mine.sets, theirScore: theirs.sets, opponent: opponent, userIsHome: userIsHome)
        }

        switch match.kind {
        case .regular:
            let tier = userTier
            applyDuel(state, tier: tier, countsForStandings: true)
            for index in match.others.indices {
                match.others[index].runToEnd()
                applyDuel(match.others[index], tier: tier, countsForStandings: true)
            }
            // 다른 다섯 리그의 같은 라운드
            for other in LeagueTier.allCases where other != tier {
                for fixture in schedules[other.index][round] {
                    ensurePlayable(fixture.home)
                    ensurePlayable(fixture.away)
                    guard var game = makeDuelMatch(home: fixture.home, away: fixture.away, kind: .regular, seed: rng.next())
                    else { continue }
                    game.runToEnd()
                    applyDuel(game, tier: other, countsForStandings: true)
                }
            }
            summary += settle(.regular)
            round += 1
        case .playoff:
            applyDuel(state, tier: userTier, countsForStandings: false)
            if let index = series.firstIndex(where: { !$0.isDecided && $0.involves(userTeamID) }),
               let homeTeam = state.home.teamID {
                recordPlayoffGame(index, home: homeTeam, homeScore: state.home.sets, awayScore: state.away.sets)
            }
            summary += settle(.playoff)
        case .friendly:
            applyDuel(state, tier: userTier, countsForStandings: false)
            summary += settle(.friendly)
            friendliesPlayed += 1
        case .cup:
            applyDuel(state, tier: userTier, countsForStandings: false)
            let roundName = cup?.roundName ?? ""
            if let homeTeam = state.home.teamID {
                recordCupTie(home: homeTeam, homeScore: state.home.sets, awayScore: state.away.sets, homeWon: state.homeWon)
            }
            summary += settleCareerCupTie(won: mine.sets > theirs.sets, opponent: opponent, roundName: roundName)
        }

        if isCareer { summary += settleCareerDuelMatch(kind: match.kind, state: state, userIsHome: userIsHome) }

        lastResult = LastResult(
            kind: match.kind, myRuns: mine.sets, theirRuns: theirs.sets,
            opponent: theirs.name, wasHome: userIsHome, summary: summary)

        tick(kind: match.kind)
    }

    /// 경기 결과를 선수 기록·순위표에 반영한다. 순위표의 득실은 세트 득실이다.
    mutating func applyDuel(_ state: DuelMatch, tier: LeagueTier, countsForStandings: Bool) {
        for (side, opponent) in [(state.home, state.away), (state.away, state.home)] {
            guard let teamID = side.teamID else { continue }
            let played = Set(state.records.flatMap { [$0.home.playerID, $0.away.playerID] }).intersection(side.lineup)
            for id in played {
                guard var player = players[id] else { continue }
                let sets = state.sets(of: id)
                if countsForStandings {
                    var line = player.duel ?? DuelLine()
                    line.games += 1
                    for record in sets { line.add(record, playerID: id) }
                    player.duel = line
                }
                player.isHot = !sets.isEmpty && sets.allSatisfy { $0.entry(for: id)?.won == true }
                player.lastStartGame = teams[teamID].gamesPlayed
                players[id] = player
                playedFactor[id] = Balance.playFactorStarter * (player.isHot ? 1.1 : 1.0)
            }
            teams[teamID].gamesPlayed += 1

            guard countsForStandings,
                  let row = standings[tier.index].firstIndex(where: { $0.teamID == teamID }),
                  let opponentID = opponent.teamID
            else { continue }
            var entry = standings[tier.index][row]
            entry.runsFor += side.sets
            entry.runsAgainst += opponent.sets
            if side.sets > opponent.sets {
                entry.wins += 1
                entry.winsAgainst[opponentID, default: 0] += 1
                teams[teamID].streak = max(1, teams[teamID].streak + 1)
            } else {
                entry.losses += 1
                teams[teamID].streak = min(-1, teams[teamID].streak - 1)
            }
            standings[tier.index][row] = entry

            // CPU 구단 수입과 인지도
            if !teams[teamID].isUser {
                teams[teamID].funds += Balance.cpuIncomePerMatch(tier)
                teams[teamID].fame += side.sets > opponent.sets ? 1.5 : 0
            }
        }
    }

    // MARK: 화면 없이 치르는 경기

    /// 1:1 대전 팀 경기를 화면 없이 끝까지 치르고 세트 점수를 돌려준다. 기록에는 넣지 않는다.
    /// 두 팀 중 하나라도 세 명이 안 되면 nil.
    func quietDuelMatch(home: TeamID, away: TeamID, bestOf: Int = DuelLineupBuilder.setsPerMatch, seed: UInt64)
        -> (home: Int, away: Int)?
    {
        guard let homeSide = duelSide(home, bestOf: bestOf), let awaySide = duelSide(away, bestOf: bestOf) else { return nil }
        var match = DuelMatch(home: homeSide, away: awaySide, bestOf: bestOf, seed: seed)
        match.runToEnd()
        return (match.home.sets, match.away.sets)
    }

    // MARK: 성적

    /// 연봉 협상에 쓰는 시즌 활약도 (0 ~ 대략 1): 세트 승률이 5할을 넘긴 만큼.
    static func duelPerformance(_ player: Player) -> Double {
        let line = player.duel ?? DuelLine()
        guard line.sets >= 4 else { return 0 }
        return max(0, line.winRate - 0.5) * 2
    }
}

/// 진행 중인 내 1:1 대전 팀 경기와, 같은 라운드의 내 리그 다른 경기들.
public struct LiveDuelMatch: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var state: DuelMatch
    public var others: [DuelMatch]
    public var userIsHome: Bool
    public var tier: LeagueTier
}

// MARK: 시상과 기록 순위

extension Game {
    mutating func giveDuelAwards() {
        for tier in LeagueTier.allCases {
            let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
            func line(_ player: Player) -> DuelLine { player.duel ?? DuelLine() }
            let regulars = everyone.filter { line($0).sets >= roundsPerSeason / 3 }
            func record(_ title: String, _ player: Player?, _ detail: (Player) -> String) {
                guard let player, let teamID = player.teamID else { return }
                awards.append(AwardRecord(
                    season: season, tier: tier, title: title, playerName: player.name,
                    teamName: teams[teamID].name, detail: detail(player),
                    isMine: isCareer ? isMyPlayer(player.id) : teamID == userTeamID))
            }
            func rate(_ player: Player) -> String { "세트 \(line(player).setWins)승 \(line(player).setLosses)패" }
            record("MVP", regulars.max { (line($0).winRate, line($0).setWins, $0.id) < (line($1).winRate, line($1).setWins, $1.id) }) {
                "\(rate($0)), 승률 \(Int((line($0).winRate * 100).rounded()))%"
            }
            record("다승왕", everyone.max { (line($0).setWins, -line($0).setLosses, $0.id) < (line($1).setWins, -line($1).setLosses, $1.id) }) { rate($0) }
            let aces = everyone.filter { line($0).aceWins > 0 }
            record("에이스 결정전의 강자", aces.max { (line($0).aceWins, -line($0).aceLosses, $0.id) < (line($1).aceWins, -line($1).aceLosses, $1.id) }) {
                "에이스 결정전 \(line($0).aceWins)승 \(line($0).aceLosses)패"
            }
        }
    }

    func duelLeaders(_ tier: LeagueTier, count: Int) -> [(title: String, rows: [Leader])] {
        let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
        func line(_ player: Player) -> DuelLine { player.duel ?? DuelLine() }
        func board(_ pool: [Player], _ value: (Player) -> Double, _ text: (Player) -> String) -> [Leader] {
            pool.sorted { (value($0), -$0.id) > (value($1), -$1.id) }.prefix(count).compactMap { player in
                guard let teamID = player.teamID else { return nil }
                return Leader(
                    playerName: player.name, teamName: teams[teamID].name, value: text(player),
                    isMine: isCareer ? isMyPlayer(player.id) : teamID == userTeamID)
            }
        }
        let regulars = everyone.filter { line($0).sets >= max(1, round / 3) }
        return [
            ("세트 승", board(everyone, { Double(line($0).setWins) }, { "\(line($0).setWins)승" })),
            ("세트 승률", board(regulars, { line($0).winRate }, { "\(Int((line($0).winRate * 100).rounded()))%" })),
            ("에이스 결정전", board(everyone.filter { line($0).aceWins > 0 }, { Double(line($0).aceWins) }, { "\(line($0).aceWins)승" })),
        ]
    }
}
