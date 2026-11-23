import Foundation

/// 진행 중인 내 농구 경기와, 같은 라운드의 내 리그 다른 경기들.
public struct LiveBasketballMatch: Codable, Equatable, Sendable {
    public var kind: MatchKind
    public var state: BasketballMatch
    public var others: [BasketballMatch]
    public var userIsHome: Bool
    public var tier: LeagueTier
}

/// 농구에서만 쓰는 부분: 경기 시작·진행·정산, 내 선수의 출전과 평점, 시상, 기록 순위.
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

    // MARK: 선수 모드: 출전

    /// 감독이 나를 선발로 쓸지. 같은 포지션에서 가장 좋은 선수와 능력을 비교하고, 감독 신뢰만큼 보정한다 (−5 ~ +5).
    func careerBasketballStarts() -> Bool {
        guard let career, let me = players[career.playerID], let teamID = me.teamID else { return false }
        let best = roster(of: teamID).filter { $0.position == me.position && $0.id != me.id }.map(\.ability).max()
        guard let best else { return true }
        return me.ability + (career.trust - 50) / 10 >= best
    }

    /// 다음 경기에 내 농구 선수가 어떻게 나오는지 (화면 안내용): 선발인지, 벤치면 몇 분쯤 뛰는지.
    public var careerBasketballPlan: (starts: Bool, minutes: Int?)? {
        guard let career, let me = players[career.playerID], me.position.sport == .basketball,
              nextMatch() != nil
        else { return nil }
        let starts = careerBasketballStarts()
        return (starts, starts ? nil : Balance.careerBenchMinutes(trust: career.trust))
    }

    /// 선발 다섯 명을 정한다. 내가 선발이면 같은 포지션의 선발 대신 들어가고, 아니면 벤치에서 시작한다.
    /// 벤치에서 시작해도 감독 신뢰에 따라 정해진 시간만큼은 반드시 뛴다.
    mutating func prepareCareerBasketballLineup() {
        guard let career, let me = players[career.playerID] else { return }
        let starts = careerBasketballStarts()
        var team = teams[userTeamID]
        team.lineupOverride = []
        guard let auto = BasketballLineupBuilder.build(team: team, players: players) else { return }
        var ids = auto.starters.map(\.id)
        if starts, !ids.contains(me.id) {
            let index = auto.starters.firstIndex { $0.slot == me.position }
                ?? ids.indices.min { (players[ids[$0]]?.ability ?? 0, $0) < (players[ids[$1]]?.ability ?? 0, $1) }
            if let index { ids[index] = me.id }
        } else if !starts, let index = ids.firstIndex(of: me.id) {
            let bench = auto.bench.compactMap { players[$0] }
            if let replacement = bench.first(where: { $0.position == me.position }) ?? bench.first {
                ids[index] = replacement.id
            }
        }
        teams[userTeamID].lineupOverride = ids == auto.starters.map(\.id) ? [] : ids
    }

    /// 경기 엔진에 넘어간 내 선수에게 플레이 스타일, 컨디션, 보장 출전 시간을 붙인다.
    func decorateCareerBasketball(_ match: inout BasketballMatch, userIsHome: Bool) {
        guard let career else { return }
        var side = userIsHome ? match.home : match.away
        guard let index = side.players.firstIndex(where: { $0.playerID == career.playerID }) else { return }
        let style = career.style ?? .balanced
        if style != .balanced { side.players[index].style = style }
        let factor = 1 + careerFormModifier
        if factor != 1 {
            func scale(_ value: inout Double) { value = clamp(value * factor, 1, 99) }
            scale(&side.players[index].shooting); scale(&side.players[index].three)
            scale(&side.players[index].passing); scale(&side.players[index].dribbling)
            scale(&side.players[index].defense); scale(&side.players[index].rebounding)
            scale(&side.players[index].speed); scale(&side.players[index].physical)
        }
        if !side.players[index].isStarter {
            side.featured = career.playerID
            side.featuredMinutes = Balance.careerBenchMinutes(trust: career.trust)
        }
        if userIsHome { match.home = side } else { match.away = side }
    }

    // MARK: 선수 모드: 평점과 정산

    /// 농구 경기에서 내 선수가 한 일과 평점. 나오지 않았으면 nil.
    /// `result`: 이겼으면 1, 졌으면 −1.
    static func careerBasketballPerformance(
        playerID: PlayerID, in side: BasketballSide, result: Int
    ) -> CareerPerformance? {
        guard let entry = side.players.first(where: { $0.playerID == playerID }), entry.hasPlayed else { return nil }
        let line = entry.line
        let minutes = max(1, line.minutes)
        let missed = line.fieldGoalsAttempted - line.fieldGoalsMade
        let missedFree = line.freeThrowsAttempted - line.freeThrowsMade
        var delta = 0.0
        delta += Double(line.points) * 0.06 + Double(line.rebounds) * 0.07
        // 연계 스타일은 도움 하나가 더 크게 평가된다.
        delta += Double(line.assists) * (entry.style == .link ? 0.14 : 0.11)
        delta += Double(line.steals) * 0.2 + Double(line.blocks) * 0.2
        delta -= Double(line.turnovers) * 0.15 + Double(missed) * 0.06 + Double(missedFree) * 0.03
        delta -= Double(line.fouls) * 0.05
        if line.isDoubleDouble { delta += 0.3 }
        delta += Double(result) * 0.2
        // 포지션마다 기록이 쌓이는 양이 달라서 기준을 맞춘다 (30분 뛴 평균 선수가 6.5 근처).
        delta += Balance.careerBasketballBaseline(entry.natural)
        // 뛴 시간이 짧으면 6.0 쪽으로 당긴다.
        let weight = min(1, 0.35 + Double(minutes) / 30 * 0.65)
        var text = "\(minutes)분 \(line.points)점"
        if line.rebounds > 0 { text += " \(line.rebounds)리바운드" }
        if line.assists > 0 { text += " \(line.assists)도움" }
        if line.steals > 0 { text += " \(line.steals)스틸" }
        if line.blocks > 0 { text += " \(line.blocks)블록" }
        if entry.fouledOut { text += " 5반칙 퇴장" }
        // 감독 신뢰는 축구의 "30분도 못 뛴 경기"와 같은 규칙으로 본다: 20분 미만이면 짧게 뛴 경기다.
        // (벤치에서 나온 선수는 평점이 6점 근처에 몰려서, 보통 규칙을 쓰면 신뢰가 내려가기만 한다.)
        // 농구는 기록이 많이 쌓여서 압도적인 날에는 평점이 10을 훌쩍 넘는다. 8.5 위로는 완만하게 올려서
        // 아주 잘한 날과 역사적인 날이 구분되게 한다 (계산값 10 → 9.0, 12 → 9.7).
        var rating = 6 + delta * weight
        if rating > 8.5 { rating = 8.5 + (rating - 8.5) * 0.35 }
        return CareerPerformance(
            rating: clamp(rating, 1, 10), line: text,
            minutes: minutes * 3 / 2, scored: line.points >= 10)
    }

    /// 내 경기 정산 (농구).
    mutating func settleCareerBasketballMatch(
        kind: MatchKind, state: BasketballMatch, userIsHome: Bool
    ) -> [String] {
        guard let career else { return [] }
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        let result = mine.points > theirs.points ? 1 : -1
        let rival = career.rival.flatMap {
            Self.careerBasketballPerformance(playerID: $0.playerID, in: theirs, result: -result)
        }
        return settleCareer(
            kind: kind,
            performance: Self.careerBasketballPerformance(playerID: career.playerID, in: mine, result: result),
            rival: rival)
    }

    /// 통산 기록: 끝난 시즌들에 진행 중인 시즌을 더한 값.
    public var careerBasketballTotals: BasketballLine {
        var line = BasketballLine()
        guard let career else { return line }
        for season in career.history { line += season.basketball ?? BasketballLine() }
        if !career.seasonClosed, let me = players[career.playerID] { line += me.basketball ?? BasketballLine() }
        return line
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
