import Foundation

/// 농구 선수 모드: 내 선수의 출전, 평점, 정산, 통산 기록.
extension Game {
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
}
