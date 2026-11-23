import Foundation

/// 선수 모드: 경기 평점과 경기 뒤 정산.
extension Game {
    // MARK: 경기 평점

    public struct CareerPerformance: Equatable, Sendable {
        public var rating: Double
        public var line: String
        /// 축구: 뛴 시간(분). 야구는 nil.
        public var minutes: Int? = nil
        /// 연속 기록에 들어가는 일을 했는지 (타자: 안타, 투수: 무자책, 축구: 골·도움, 골키퍼: 무실점).
        public var scored: Bool? = nil
    }

    /// 이 경기에서 내 선수가 한 일과 평점 (1.0~10.0, 6.0이 "무난했다"). 나오지 않았으면 nil.
    /// `result`: 팀이 이겼으면 1, 졌으면 −1, 비겼으면 0.
    static func careerPerformance(playerID: PlayerID, in side: MatchTeam, result: Int) -> CareerPerformance? {
        let teamShift = Double(result) * 0.2
        if let batter = side.batters.first(where: { $0.playerID == playerID }) {
            let line = batter.line
            guard line.plateAppearances > 0 else { return nil }
            let singles = line.hits - line.doubles - line.triples - line.homeRuns
            let quietOuts = max(0, line.atBats - line.hits - line.strikeouts)
            var rating = 6.1
            rating += Double(singles) * 0.55 + Double(line.doubles) * 0.8
            rating += Double(line.triples) * 1.0 + Double(line.homeRuns) * 1.4
            rating += Double(line.runsBattedIn) * 0.3 + Double(line.runs) * 0.2
            rating += Double(line.walks) * 0.25 + Double(line.steals) * 0.3
            rating -= Double(line.strikeouts) * 0.2 + Double(quietOuts) * 0.15
            var text = "\(line.atBats)타수 \(line.hits)안타"
            if line.homeRuns > 0 { text += " \(line.homeRuns)홈런" }
            if line.runsBattedIn > 0 { text += " \(line.runsBattedIn)타점" }
            if line.walks > 0 { text += " \(line.walks)볼넷" }
            if line.steals > 0 { text += " \(line.steals)도루" }
            return CareerPerformance(rating: clamp(rating + teamShift, 1, 10), line: text, scored: line.hits > 0)
        }
        if let index = side.pitchers.firstIndex(where: { $0.playerID == playerID && $0.hasEntered }) {
            let line = side.pitchers[index].line
            let unearned = max(0, line.runs - line.earnedRuns)
            var rating = 6.0
            if index == 0 {
                // 선발은 점수를 주는 것이 보통이라 기준을 조금 높게 잡는다.
                rating += 0.2
                rating += Double(line.outs) * 0.12 - Double(line.earnedRuns) * 0.45 - Double(unearned) * 0.2
                rating += Double(line.strikeouts) * 0.08 - Double(line.walks) * 0.12
                rating -= Double(line.hits) * 0.06 + Double(line.homeRuns) * 0.2
                rating += Double(line.wins) * 0.5
            } else {
                rating += Double(line.outs) * 0.25 - Double(line.earnedRuns) * 0.9 - Double(unearned) * 0.3
                rating += Double(line.strikeouts) * 0.1 - Double(line.walks) * 0.15 - Double(line.hits) * 0.1
                rating += Double(line.saves) * 1.0 + Double(line.wins) * 0.3
            }
            var text = "\(line.innings)이닝 \(line.runs)실점 \(line.strikeouts)탈삼진"
            if line.wins > 0 { text += " 승리" }
            if line.losses > 0 { text += " 패전" }
            if line.saves > 0 { text += " 세이브" }
            return CareerPerformance(rating: clamp(rating + teamShift, 1, 10), line: text, scored: line.earnedRuns == 0)
        }
        return nil
    }

    /// 평점에 따른 감독 신뢰 변화: 7.0 이상이면 오르고 6.0 아래면 내린다.
    /// 축구에서 30분도 못 뛴 교체 출전은 평점이 6점 근처에 몰리므로 기준을 따로 둔다.
    static func careerTrustChange(rating: Double, minutes: Int? = nil) -> Double {
        if let minutes, minutes < 30 {
            return rating >= 6.5 ? 0.5 : rating < 5.7 ? -0.5 : 0
        }
        if rating >= 7 { return min(6, 1 + (rating - 7) * 3) }
        if rating < 6 { return max(-6, -1 - (6 - rating) * 3) }
        return 0
    }

    /// 진행 중인 경기에서 지금까지의 내 선수 평점.
    public var careerLivePerformance: CareerPerformance? {
        guard let career else { return nil }
        if let liveFootball {
            let mine = liveFootball.userIsHome ? liveFootball.state.home : liveFootball.state.away
            let theirs = liveFootball.userIsHome ? liveFootball.state.away : liveFootball.state.home
            return Self.careerFootballPerformance(
                playerID: career.playerID, in: mine, conceded: theirs.goals, result: 0)
        }
        if let liveBasketball {
            let mine = liveBasketball.userIsHome ? liveBasketball.state.home : liveBasketball.state.away
            return Self.careerBasketballPerformance(playerID: career.playerID, in: mine, result: 0)
        }
        guard let live else { return nil }
        let mine = live.userIsHome ? live.state.home : live.state.away
        return Self.careerPerformance(playerID: career.playerID, in: mine, result: 0)
    }

    /// 내 경기 정산 (야구).
    mutating func settleCareerMatch(kind: MatchKind, state: MatchState, userIsHome: Bool) -> [String] {
        guard let career else { return [] }
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        let result = mine.runs > theirs.runs ? 1 : mine.runs < theirs.runs ? -1 : 0
        let rival = career.rival.flatMap { Self.careerPerformance(playerID: $0.playerID, in: theirs, result: -result) }
        return settleCareer(
            kind: kind, performance: Self.careerPerformance(playerID: career.playerID, in: mine, result: result),
            rival: rival)
    }

    /// 내 경기 정산 (축구).
    mutating func settleCareerFootballMatch(kind: MatchKind, state: FootballMatch, userIsHome: Bool) -> [String] {
        guard let career else { return [] }
        let mine = userIsHome ? state.home : state.away
        let theirs = userIsHome ? state.away : state.home
        let won = state.result == (userIsHome ? .homeWin : .awayWin)
        let result = won ? 1 : state.result == .draw ? 0 : -1
        let rival = career.rival.flatMap {
            Self.careerFootballPerformance(playerID: $0.playerID, in: theirs, conceded: mine.goals, result: -result)
        }
        return settleCareer(
            kind: kind,
            performance: Self.careerFootballPerformance(
                playerID: career.playerID, in: mine, conceded: theirs.goals, result: result),
            rival: rival)
    }

    /// 평점에 따라 감독 신뢰, 명성, 연봉을 정산한다. 훈련 횟수도 다시 채운다.
    /// `rival`: 상대 구단에 라이벌이 있고 그 선수가 뛰었으면 그 평점.
    mutating func settleCareer(
        kind: MatchKind, performance: CareerPerformance?, rival: CareerPerformance? = nil
    ) -> [String] {
        guard var career, !career.retired, let me = players[career.playerID] else { return [] }
        var lines: [String] = []

        // 선발 투수는 등판하지 않는 날에 훈련을 한 번 더 한다.
        career.sessionsLeft = Balance.careerSessionsPerMatch + (me.position == .starter && performance == nil ? 1 : 0)
        career.activityDone = nil
        career.lastCritical = nil
        career.matchesAtClub += 1
        career.subMinute = nil
        career.lastRating = performance?.rating
        career.lastLine = performance?.line
        if let performance {
            lines.append("\(me.name) 평점 \(String(format: "%.1f", performance.rating)) · \(performance.line)")
            // 친선 경기는 절반만 반영한다.
            let weight = kind == .friendly ? 0.5 : 1.0
            let before = career.trust
            career.trust = clamp(
                career.trust + Self.careerTrustChange(rating: performance.rating, minutes: performance.minutes) * weight,
                0, 100)
            let moved = Int((career.trust - before).rounded())
            if moved != 0 { lines.append("감독 신뢰 \(moved > 0 ? "+" : "")\(moved)") }
            if kind != .friendly {
                let cap = Balance.careerFameCap(teams[userTeamID].tier)
                // 선발 투수는 나오는 경기가 적어서 한 경기가 더 크게 반영된다.
                // 평점이 6점대에 몰린 종목(축구, 농구)은 기준을 낮추고 크게 반영한다.
                let rarity = me.position == .starter ? 3.0 : me.position.sport.careerFameWeight
                // 기세가 붙어 있으면 이름이 더 빨리 알려진다.
                let momentum = (career.streak ?? 0) >= Balance.careerStreakLength ? Balance.careerMomentumFame : 1
                if career.fame < cap {
                    career.fame += max(0, performance.rating - me.position.sport.careerRatingBaseline) * 0.8 * rarity * momentum
                        * (cap - career.fame) / cap
                }
            }
            if kind == .regular {
                career.seasonRatedGames += 1
                career.seasonRatingTotal += performance.rating
            }
        } else {
            lines.append(me.position == .starter
                ? "\(me.name): 등판하지 않는 날입니다." : "\(me.name): 출전하지 않았습니다.")
        }
        if kind == .regular {
            let pay = me.contract.salary / roundsPerSeason
            career.earnings += pay
            lines.append("연봉 ₩\(pay.formatted())")
        }
        if kind != .friendly { lines += settleCareerRival(&career, mine: performance, rival: rival) }
        lines += updateCareerScouts(&career, me: me, performance: performance, kind: kind)
        lines += updateCareerForm(&career, performance: performance, kind: kind)
        self.career = career
        // 토큰으로 사서 치른 경기는 실전 경험으로 능력이 조금 오른다.
        // 내 선수가 나오지 않은 날(선발 투수가 쉬는 날, 벤치, 출장 정지)이면 다음에 나온 경기에서 받는다.
        if extraMatchPending == true, let performance {
            extraMatchPending = nil
            let gained = applyCareerExtraMatchGain(rating: performance.rating)
            if gained > 0 { lines.append("실전 경험: 능력 +\(String(format: "%.2f", gained))") }
        }
        let ability = players[me.id]?.ability ?? me.ability
        self.career?.peakAbility = max(career.peakAbility, ability)
        if let line = refreshCareerRival() { lines.append(line) }
        return lines
    }

    // MARK: 경기 평점 (축구)

    /// 축구 경기에서 내 선수가 한 일과 평점. 나오지 않았으면 nil.
    /// `conceded`: 우리 팀이 내준 골. `result`: 이겼으면 1, 졌으면 −1, 비겼으면 0.
    static func careerFootballPerformance(
        playerID: PlayerID, in side: FootballSide, conceded: Int, result: Int
    ) -> CareerPerformance? {
        guard let entry = side.players.first(where: { $0.playerID == playerID }), entry.hasPlayed else { return nil }
        let line = entry.line
        let detail = entry.detail ?? FootballDetail()
        let minutes = min(120, max(1, detail.minutes))
        var delta = 0.0
        // 연계 스타일은 도움 하나가 더 크게 평가된다.
        delta += Double(line.goals) * 1.0 + Double(line.assists) * (entry.style == .link ? 0.8 : 0.6)
        delta += Double(line.shotsOnTarget) * 0.15
        delta += Double(detail.advances) * 0.05 + Double(detail.tackles) * 0.12 + Double(detail.clearances) * 0.12
        delta -= Double(detail.fouls) * 0.1 + Double(line.yellowCards) * 0.3 + Double(line.redCards) * 1.5
        if entry.natural == .goalkeeper {
            // 막아 낸 골: 비슷한 실력의 골키퍼라면 유효 슈팅의 36%쯤이 들어간다. 그보다 덜 먹은 만큼이 골키퍼의 몫이다.
            // 바쁜 경기에서 선방만 많이 해도, 실점이 같은 비율로 따라오면 평점이 오르지 않는다.
            let prevented = Double(line.saves) * Balance.careerKeeperShotGoalRate
                - Double(line.conceded) * (1 - Balance.careerKeeperShotGoalRate)
            delta += prevented * Balance.careerKeeperPreventedWeight
        }
        // 무실점: 골키퍼와 수비수가 60분 이상 뛰었을 때. 팀이 강해서 슈팅을 받지 않은 날에도 평가받게 한다.
        if conceded == 0, minutes >= 60 {
            if entry.natural == .goalkeeper { delta += 0.8 } else if entry.natural == .defender { delta += 0.5 }
        }
        delta += Double(result) * 0.2
        // 포지션마다 기록이 쌓이는 양이 달라서 기준을 맞춘다 (90분 뛴 평균 선수가 6.5 근처).
        delta += Balance.careerFootballBaseline(entry.natural)
        // 뛴 시간이 짧으면 6.0 쪽으로 당긴다.
        let weight = min(1, 0.35 + Double(minutes) / 90 * 0.65)
        var text = "\(minutes)분"
        if entry.natural == .goalkeeper {
            text += " 선방 \(line.saves) 실점 \(line.conceded)"
        } else {
            if line.goals > 0 { text += " \(line.goals)골" }
            if line.assists > 0 { text += " \(line.assists)도움" }
            text += " 슈팅 \(line.shots)"
            if detail.tackles + detail.clearances > 0 { text += " 수비 \(detail.tackles + detail.clearances)" }
        }
        if line.redCards > 0 { text += " 퇴장" } else if line.yellowCards > 0 { text += " 경고" }
        let scored = entry.natural == .goalkeeper ? line.conceded == 0 : line.goals + line.assists > 0
        return CareerPerformance(rating: clamp(6 + delta * weight, 1, 10), line: text, minutes: minutes, scored: scored)
    }
}
