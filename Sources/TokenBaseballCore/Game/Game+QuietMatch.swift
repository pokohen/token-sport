import Foundation

/// 화면 없이 끝까지 치르는 경기 (플레이오프, 컵대회, CPU끼리의 승부). 종목에 맞는 엔진을 고른다.
extension Game {
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
        switch sport {
        case .football:
            guard var match = makeFootballMatch(home: home, away: away, kind: kind, seed: seed, rules: footballRules)
            else { return nil }
            match.runToEnd()
            applyFootball(match, tier: tier, countsForStandings: false, competitive: true)
            return QuietResult(
                homeScore: match.home.goals, awayScore: match.away.goals,
                homeWon: match.result == .homeWin, shootout: match.wentToShootout)
        case .basketball:
            guard var match = makeBasketballMatch(home: home, away: away, seed: seed) else { return nil }
            match.runToEnd()
            applyBasketball(match, tier: tier, countsForStandings: false)
            return QuietResult(
                homeScore: match.home.points, awayScore: match.away.points,
                homeWon: match.result == .homeWin, shootout: false)
        case .duel:
            guard let score = quietDuelMatch(home: home, away: away, seed: seed) else { return nil }
            return QuietResult(homeScore: score.home, awayScore: score.away, homeWon: score.home > score.away, shootout: false)
        case .baseball:
            break
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
        switch sport {
        case .football:
            guard var match = makeFootballMatch(home: home, away: away, kind: kind, seed: seed) else { return nil }
            match.runToEnd()
            return match.result == .homeWin
        case .basketball:
            guard var match = makeBasketballMatch(home: home, away: away, seed: seed) else { return nil }
            match.runToEnd()
            return match.result == .homeWin
        case .duel:
            return quietDuelMatch(home: home, away: away, seed: seed).map { $0.home > $0.away }
        case .baseball:
            break
        }
        guard var game = makeMatch(home: home, away: away, kind: kind, tier: tier, seed: seed) else { return nil }
        game.runToEnd()
        return game.home.runs > game.away.runs
    }
}
