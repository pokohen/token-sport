import Foundation

/// e스포츠 1:1 대전 선수 모드: 내 선수의 세트 평점, 팬, 정산, 통산 기록.
/// 출전 순서는 `Game/Game+Duel.swift`의 `duelLineup` (네 경기에 한 번은 세트를 받는다).
extension Game {
    // MARK: 출전

    /// 다음 경기에 내 선수가 어떻게 나오는지 (화면 안내용): 에이스(1세트와 결정전), 2세트, 또는 나오지 않음.
    public var careerDuelPlan: (setIndex: Int?, isAce: Bool)? {
        guard let career, let me = players[career.playerID], me.position.sport == .duel, let team = me.teamID,
              let next = nextMatch()
        else { return nil }
        let bestOf = next.kind == .playoff ? 5 : DuelLineupBuilder.setsPerMatch
        guard let lineup = duelLineup(team, bestOf: bestOf), let index = lineup.firstIndex(of: me.id) else {
            return (nil, false)
        }
        return (index, index == 0)
    }

    /// 경기 전에 플레이 스타일을 고른다.
    public mutating func setCareerDuelStyle(_ style: DuelStyle) {
        guard career != nil else { return }
        career?.duelStyle = style == .balanced ? nil : style
    }

    // MARK: 평점

    /// 세트 하나의 평점 (6.0이 "무난했다"). 이기면 오르고 지면 내린다. 병력·일꾼 교환, 빨리 끝낸 완승, 역전,
    /// 상대가 얼마나 강했는지를 본다. 에이스 결정전과 결승에서는 더 크게 움직인다.
    static func duelSetRating(won: Bool, me: DuelMatch.SetStats, them: DuelMatch.SetStats, ticks: Int, stakes: DuelStakes,
                              decider: Bool) -> Double {
        var delta = won ? Balance.careerDuelWinShift : Balance.careerDuelLossShift
        let traded = me.armyKilled + me.armyLost
        delta += (me.armyKilled - me.armyLost) / max(20, traded) * 0.8
        delta += clamp((me.workersKilled - me.workersLost) / 30, -0.5, 0.5)
        if won, ticks < 50 { delta += 0.3 }
        if won, me.worstDeficit >= 0.3 { delta += 0.4 }
        delta += clamp((them.overall - me.overall) * 0.03, -0.5, 0.5)
        if decider || stakes == .final { delta *= 1.25 }
        return clamp(6 + delta, 1, 10)
    }

    /// 팀 경기에서 내 선수가 한 일과 평점 (나온 세트의 평균). 나오지 않았으면 nil.
    static func careerDuelPerformance(playerID: PlayerID, in match: DuelMatch) -> CareerPerformance? {
        let sets = match.sets(of: playerID)
        guard !sets.isEmpty else { return nil }
        var total = 0.0
        var parts: [String] = []
        for record in sets {
            guard let entry = record.entry(for: playerID) else { continue }
            total += duelSetRating(
                won: entry.won, me: entry.me, them: entry.them, ticks: record.ticks, stakes: record.stakes,
                decider: record.decider)
            let title = record.decider ? "\(record.number)세트(에이스 결정전)" : "\(record.number)세트"
            parts.append("\(title) \(entry.won ? "승" : "패") 대 \(entry.them.race.label)")
        }
        let wins = sets.filter { $0.entry(for: playerID)?.won == true }.count
        return CareerPerformance(rating: total / Double(sets.count), line: parts.joined(separator: " · "), scored: wins > 0)
    }

    // MARK: 팬

    /// 팬 수가 바뀐 만큼 명성을 다시 계산한다 (e스포츠는 팬 수 하나만 쌓는다).
    mutating func syncDuelFame() {
        guard let fans = career?.fans else { return }
        career?.fame = Balance.duelFame(fans: fans)
    }

    /// 세트 결과로 팬이 는다. 위 리그일수록, 에이스 결정전과 플레이오프일수록 많이 는다. 연패하면 조금 준다.
    mutating func gainDuelFans(_ match: DuelMatch, kind: MatchKind) -> [String] {
        guard var career, let me = players[career.playerID] else { return [] }
        let tier = teams[userTeamID].tier
        var fans = career.fans ?? 0
        let before = fans
        for record in match.sets(of: me.id) {
            guard let entry = record.entry(for: me.id), entry.won else { continue }
            var gain = Double(Balance.duelFanBase(tier)) + Double(fans) * Balance.duelFanShare
            if record.decider { gain *= 2 }
            if kind == .playoff { gain *= 2 }
            if kind == .friendly { gain *= 0.3 }
            fans += Int(gain.rounded())
        }
        if (career.streak ?? 0) <= -3, kind != .friendly {
            fans -= Int((Double(fans) * Balance.duelFanSlumpLoss).rounded())
        }
        fans = max(0, fans)
        career.fans = fans
        self.career = career
        syncDuelFame()
        guard fans != before else { return [] }
        let moved = fans - before
        return ["팬 \(moved > 0 ? "+" : "−")\(fansText(abs(moved))) (\(fansText(fans)))"]
    }

    // MARK: 정산

    mutating func settleCareerDuelMatch(kind: MatchKind, state: DuelMatch, userIsHome: Bool) -> [String] {
        guard let career else { return [] }
        let theirs = userIsHome ? state.away : state.home
        let rival = career.rival.flatMap { rival in
            theirs.lineup.contains(rival.playerID) ? Self.careerDuelPerformance(playerID: rival.playerID, in: state) : nil
        }
        var lines = settleCareer(
            kind: kind, performance: Self.careerDuelPerformance(playerID: career.playerID, in: state), rival: rival)
        lines += gainDuelFans(state, kind: kind)
        return lines
    }

    /// 통산 기록: 끝난 시즌들에 진행 중인 시즌을 더한 값.
    public var careerDuelTotals: DuelLine {
        var line = DuelLine()
        guard let career else { return line }
        for season in career.history { line += season.duel ?? DuelLine() }
        if !career.seasonClosed, let me = players[career.playerID] { line += me.duel ?? DuelLine() }
        return line
    }
}

/// "3.2만 명", "1,240명", "1,000만 명".
public func fansText(_ fans: Int) -> String {
    switch fans {
    case ..<10_000: return "\(fans.formatted())명"
    case ..<100_000_000:
        let man = Double(fans) / 10_000
        return man < 100 ? "\(String(format: "%.1f", man).replacingOccurrences(of: ".0", with: ""))만 명" : "\(Int(man).formatted())만 명"
    default:
        return "\(String(format: "%.1f", Double(fans) / 100_000_000))억 명"
    }
}
