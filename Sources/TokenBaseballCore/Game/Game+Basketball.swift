import Foundation

/// 농구에서만 쓰는 부분: 경기 시작·진행·정산, 시상, 기록 순위. 내 선수의 출전과 평점은 `Career/Game+CareerBasketball.swift`.
/// 시즌 흐름, 승강(야구 방식), 컵대회, 계약과 이적은 다른 종목과 같은 코드를 쓴다.
extension Game {
    // MARK: 경기 만들기

    func basketballRules(home: TeamID) -> BasketballRules {
        BasketballRules(homeEdge: Balance.stadiumHomeEdge[teams[home].stadiumLevel - 1])
    }

    func makeBasketballMatch(home: TeamID, away: TeamID, seed: UInt64) -> BasketballMatch? {
        guard let homeSide = BasketballLineupBuilder.side(team: teams[home], players: players),
              let awaySide = BasketballLineupBuilder.side(team: teams[away], players: players)
        else { return nil }
        return BasketballMatch(away: awaySide, home: homeSide, rules: basketballRules(home: home), seed: seed)
    }

    // MARK: 경기 시작과 진행

    mutating func startBasketballMatch(
        _ next: NextMatch, home: TeamID, away: TeamID, tier: LeagueTier, now: Date
    ) throws {
        guard var state = makeBasketballMatch(home: home, away: away, seed: rng.next()) else {
            throw GameError("경기를 시작할 수 없습니다.")
        }
        if isCareer { decorateCareerBasketball(&state, userIsHome: next.userIsHome) }
        // 같은 라운드의 내 리그 다른 경기는 함께 돌아가며 "타 구장 소식"으로 보인다.
        var others: [BasketballMatch] = []
        if next.kind == .regular {
            for fixture in schedules[userTier.index][round] where !fixture.involves(userTeamID) {
                ensurePlayable(fixture.home)
                ensurePlayable(fixture.away)
                if let other = makeBasketballMatch(home: fixture.home, away: fixture.away, seed: rng.next()) {
                    others.append(other)
                }
            }
        }
        if charges >= Balance.maxMatchCharges { chargeAnchor = now }
        charges -= 1
        liveBasketball = LiveBasketballMatch(
            kind: next.kind, state: state, others: others, userIsHome: next.userIsHome, tier: tier)
        lastResult = nil
    }

    mutating func stepBasketballMatch() -> [MatchEvent] {
        guard var match = liveBasketball else { return [] }
        let events = match.state.step()
        for index in match.others.indices where !match.others[index].isFinished {
            match.others[index].step()
        }
        liveBasketball = match
        if match.state.isFinished { finishLiveBasketballMatch() }
        return events
    }

    // MARK: 경기 끝

    mutating func finishLiveBasketballMatch() {
        guard var match = liveBasketball else { return }
        liveBasketball = nil
        playedFactor = [:]
        let state = match.state
        let userIsHome = match.userIsHome
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        var summary: [String] = []

        func settle(_ kind: MatchKind) -> [String] {
            settleUserMatch(
                kind: kind, myScore: mine.points, theirScore: theirs.points, opponent: theirs.teamID,
                userIsHome: userIsHome)
        }

        switch match.kind {
        case .regular:
            let tier = userTier
            applyBasketball(state, tier: tier, countsForStandings: true)
            for index in match.others.indices {
                match.others[index].runToEnd()
                applyBasketball(match.others[index], tier: tier, countsForStandings: true)
            }
            // 다른 다섯 리그의 같은 라운드
            for other in LeagueTier.allCases where other != tier {
                for fixture in schedules[other.index][round] {
                    ensurePlayable(fixture.home)
                    ensurePlayable(fixture.away)
                    guard var game = makeBasketballMatch(home: fixture.home, away: fixture.away, seed: rng.next())
                    else { continue }
                    game.runToEnd()
                    applyBasketball(game, tier: other, countsForStandings: true)
                }
            }
            summary += settle(.regular)
            round += 1
        case .playoff:
            applyBasketball(state, tier: userTier, countsForStandings: false)
            if let index = series.firstIndex(where: { !$0.isDecided && $0.involves(userTeamID) }) {
                recordPlayoffGame(
                    index, home: state.home.teamID, homeScore: state.home.points, awayScore: state.away.points)
            }
            summary += settle(.playoff)
        case .friendly:
            applyBasketball(state, tier: userTier, countsForStandings: false)
            summary += settle(.friendly)
            friendliesPlayed += 1
        case .cup:
            applyBasketball(state, tier: userTier, countsForStandings: false)
            let roundName = cup?.roundName ?? ""
            recordCupTie(
                home: state.home.teamID, homeScore: state.home.points, awayScore: state.away.points,
                homeWon: state.result == .homeWin)
            summary += settleCareerCupTie(
                won: mine.points > theirs.points, opponent: theirs.teamID, roundName: roundName)
        }

        if isCareer { summary += settleCareerBasketballMatch(kind: match.kind, state: state, userIsHome: userIsHome) }

        lastResult = LastResult(
            kind: match.kind, myRuns: mine.points, theirRuns: theirs.points,
            opponent: theirs.name, wasHome: userIsHome, summary: summary)

        tick(kind: match.kind)
    }

    /// 경기 결과를 선수 기록·순위표에 반영한다.
    mutating func applyBasketball(_ state: BasketballMatch, tier: LeagueTier, countsForStandings: Bool) {
        for (side, opponent) in [(state.home, state.away), (state.away, state.home)] {
            let teamID = side.teamID
            for entry in side.players where entry.hasPlayed {
                guard var player = players[entry.playerID] else { continue }
                if countsForStandings {
                    var line = player.basketball ?? BasketballLine()
                    line += entry.line
                    player.basketball = line
                }
                player.isHot = entry.line.points >= 18 || entry.line.isDoubleDouble
                players[player.id] = player
                playedFactor[player.id] = entry.isStarter
                    ? Balance.playFactorStarter * (player.isHot ? 1.1 : 1.0) : Balance.playFactorSub
            }
            teams[teamID].gamesPlayed += 1

            guard countsForStandings,
                  let row = standings[tier.index].firstIndex(where: { $0.teamID == teamID })
            else { continue }
            var entry = standings[tier.index][row]
            entry.runsFor += side.points
            entry.runsAgainst += opponent.points
            if side.points > opponent.points {
                entry.wins += 1
                entry.winsAgainst[opponent.teamID, default: 0] += 1
                teams[teamID].streak = max(1, teams[teamID].streak + 1)
            } else {
                entry.losses += 1
                teams[teamID].streak = min(-1, teams[teamID].streak - 1)
            }
            standings[tier.index][row] = entry

            // CPU 구단 수입과 인지도
            if !teams[teamID].isUser {
                teams[teamID].funds += Balance.cpuIncomePerMatch(tier)
                teams[teamID].fame += side.points > opponent.points ? 1.5 : 0
            }
        }
    }

    // MARK: 성적

    /// 연봉 협상에 쓰는 시즌 활약도 (0 ~ 대략 1).
    static func basketballPerformance(_ player: Player) -> Double {
        let line = player.basketball ?? BasketballLine()
        guard line.games > 0 else { return 0 }
        return Self.basketballEfficiency(line) / 30
    }

    /// 경기당 공헌도: 득점 + 리바운드 + 어시스트 + 스틸 + 블록 − 실책.
    static func basketballEfficiency(_ line: BasketballLine) -> Double {
        guard line.games > 0 else { return 0 }
        return Double(line.points + line.rebounds + line.assists + line.steals + line.blocks - line.turnovers)
            / Double(line.games)
    }

    mutating func giveBasketballAwards() {
        for tier in LeagueTier.allCases {
            let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
            let regulars = everyone.filter { ($0.basketball?.games ?? 0) >= roundsPerSeason / 2 }
            func line(_ player: Player) -> BasketballLine { player.basketball ?? BasketballLine() }

            func record(_ title: String, _ player: Player?, _ detail: (Player) -> String) -> Player? {
                guard let player, let teamID = player.teamID else { return nil }
                awards.append(AwardRecord(
                    season: season, tier: tier, title: title, playerName: player.name,
                    teamName: teams[teamID].name, detail: detail(player),
                    isMine: isCareer ? isMyPlayer(player.id) : teamID == userTeamID))
                return player
            }
            func average(_ value: Double) -> String { String(format: "%.1f", value) }

            let mvp = record("MVP", regulars.max {
                (Self.basketballEfficiency(line($0)), $0.id) < (Self.basketballEfficiency(line($1)), $1.id)
            }) {
                "평균 \(average(line($0).pointsPerGame))점 \(average(line($0).reboundsPerGame))리바운드 \(average(line($0).assistsPerGame))도움"
            }
            _ = record("득점왕", regulars.max { (line($0).pointsPerGame, $0.id) < (line($1).pointsPerGame, $1.id) }) {
                "평균 \(average(line($0).pointsPerGame))점"
            }
            _ = record("리바운드왕", regulars.max {
                (line($0).reboundsPerGame, $0.id) < (line($1).reboundsPerGame, $1.id)
            }) {
                "평균 \(average(line($0).reboundsPerGame))리바운드"
            }
            _ = record("어시스트왕", regulars.max {
                (line($0).assistsPerGame, $0.id) < (line($1).assistsPerGame, $1.id)
            }) {
                "평균 \(average(line($0).assistsPerGame))도움"
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

    func basketballLeaders(_ tier: LeagueTier, count: Int) -> [(title: String, rows: [Leader])] {
        // 팀이 치른 경기의 절반은 뛰어야 평균 순위에 든다.
        let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
            .filter { ($0.basketball?.games ?? 0) >= max(1, round / 2) }
        func line(_ player: Player) -> BasketballLine { player.basketball ?? BasketballLine() }
        func per(_ value: Int, _ player: Player) -> Double { Double(value) / Double(max(1, line(player).games)) }
        func board(_ value: @escaping (Player) -> Double) -> [Leader] {
            everyone.sorted { (value($0), -$0.id) > (value($1), -$1.id) }.prefix(count).map {
                Leader(
                    playerName: $0.name, teamName: $0.teamID.map { teams[$0].name } ?? "",
                    value: String(format: "%.1f", value($0)), isMine: isCareer ? isMyPlayer($0.id) : $0.teamID == userTeamID)
            }
        }
        return [
            ("득점", board { line($0).pointsPerGame }),
            ("리바운드", board { line($0).reboundsPerGame }),
            ("어시스트", board { line($0).assistsPerGame }),
            ("스틸", board { per(line($0).steals, $0) }),
            ("블록", board { per(line($0).blocks, $0) }),
            ("3점슛", board { per(line($0).threesMade, $0) }),
        ]
    }
}
