import Foundation

/// 컵대회의 한 경기. 단판이고 반드시 승부가 난다.
public struct CupTie: Codable, Equatable, Sendable {
    public var home: TeamID
    public var away: TeamID
    public var homeScore: Int?
    public var awayScore: Int?
    public var winner: TeamID?
    /// 축구: 승부차기로 갈렸는지.
    public var shootout = false

    public func involves(_ team: TeamID) -> Bool { home == team || away == team }
    public func opponent(of team: TeamID) -> TeamID { home == team ? away : home }
    public var isPlayed: Bool { winner != nil }
}

/// 컵대회: 여섯 리그의 모든 구단(야구 60개, 축구 120개)이 나오는 단판 승부. 선수 모드에서만 열린다.
/// 1부의 강한 팀들(야구 네 팀, 축구 여덟 팀)이 1라운드를 쉬고, 그 뒤로는 매 라운드 다시 추첨한다.
public struct Cup: Codable, Equatable, Sendable {
    public var season: Int
    /// 지금 치를(또는 치르는 중인) 라운드. 0 = 1라운드. 대회가 끝나면 치른 라운드 수.
    public var roundIndex = 0
    /// 지금 라운드의 대진.
    public var ties: [CupTie] = []
    /// 이번 라운드를 쉬는 구단 (1라운드에만 있다).
    public var byes: [TeamID] = []
    /// 끝난 라운드들.
    public var history: [[CupTie]] = []
    /// 리그 일정상 이 라운드를 치를 때가 됐는지.
    public var isDue = false
    public var champion: TeamID?

    /// 라운드 이름: 쉬는 구단이 있는 첫 라운드는 "1라운드", 그 뒤로는 남은 구단 수로 부른다.
    public static func roundName(ties: Int, first: Bool) -> String {
        if first, ties != 1 { return "1라운드" }
        switch ties {
        case ...1: return "결승"
        case 2: return "준결승"
        default: return "\(ties * 2)강"
        }
    }

    public var isFinished: Bool { champion != nil }
    public var roundName: String {
        isFinished ? "결승" : Self.roundName(ties: ties.count, first: roundIndex == 0)
    }
    /// 이 대회의 전체 라운드 수 (60팀이면 6, 120팀이면 7).
    public var totalRounds: Int {
        if isFinished { return history.count }
        var alive = ties.count * 2 + byes.count
        var rounds = history.count
        while alive > 1 {
            alive = (alive + 1) / 2
            rounds += 1
        }
        return rounds
    }

    /// 아직 대회에 남아 있는지.
    public func isAlive(_ team: TeamID) -> Bool {
        if let champion { return champion == team }
        return byes.contains(team) || ties.contains { $0.involves(team) && ($0.winner == nil || $0.winner == team) }
    }

    /// 그 구단이 지금까지 치른 경기 (라운드 이름과 함께).
    public func path(of team: TeamID) -> [(round: String, tie: CupTie)] {
        var result: [(String, CupTie)] = []
        for (index, round) in history.enumerated() {
            if let tie = round.first(where: { $0.involves(team) }) {
                result.append((Self.roundName(ties: round.count, first: index == 0), tie))
            }
        }
        if !isFinished, let tie = ties.first(where: { $0.involves(team) && $0.isPlayed }) {
            result.append((roundName, tie))
        }
        return result
    }
}

extension Game {
    // MARK: 대회 만들기와 추첨

    /// 선수 모드에서 이번 시즌 컵대회가 없으면 만든다.
    mutating func ensureCup() {
        guard isCareer, sport != .duel, cup?.season != season else { return }
        var fresh = Cup(season: season)
        // 1부에서 가장 강한 팀들은 1라운드를 쉰다 (60팀이면 네 팀이 쉬어 32팀, 120팀이면 여덟 팀이 쉬어 64팀이 남는다).
        let seeds = teams(in: .pro).sorted { (strength(of: $0.id), -$0.id) > (strength(of: $1.id), -$1.id) }
            .prefix(Balance.cupByes(entrants: teams.count)).map(\.id)
        fresh.byes = Array(seeds)
        fresh.ties = drawCup(teams.map(\.id).filter { !seeds.contains($0) })
        cup = fresh
    }

    /// 추첨: 섞어서 둘씩 묶는다. 아랫 리그 구단이 홈에서 치른다 (같은 리그면 먼저 뽑힌 쪽).
    mutating func drawCup(_ entrants: [TeamID]) -> [CupTie] {
        let order = rng.shuffled(entrants.sorted())
        return stride(from: 0, to: order.count - 1, by: 2).map { index in
            let first = order[index], second = order[index + 1]
            return teams[second].tier > teams[first].tier
                ? CupTie(home: second, away: first) : CupTie(home: first, away: second)
        }
    }

    // MARK: 일정

    /// 다음에 치를 내 컵 경기. 때가 되지 않았거나 이미 떨어졌으면 nil.
    public var pendingCupTie: CupTie? {
        guard let cup, cup.isDue, !cup.isFinished else { return nil }
        return cup.ties.first { $0.involves(userTeamID) && !$0.isPlayed }
    }

    /// 다음 컵 라운드가 리그 몇 라운드 뒤에 열리는지. 대회가 끝났으면 nil.
    public var nextCupLeagueRound: Int? {
        guard let cup, !cup.isFinished else { return nil }
        let timetable = Balance.cupAfterRounds(total: cup.totalRounds)
        guard cup.roundIndex < timetable.count else { return nil }
        // 일정이 짧은 시즌에도 결승은 마지막 리그 라운드 전에 열린다.
        return min(timetable[cup.roundIndex], roundsPerSeason - 1)
    }

    /// 리그 경기를 하나 마친 뒤: 컵 라운드를 치를 때가 됐으면 연다.
    /// 내 구단의 경기가 없으면(쉬는 라운드, 이미 탈락) 그 자리에서 라운드를 끝낸다.
    mutating func openCupRoundIfDue() {
        ensureCup()
        guard let cup, !cup.isFinished else { return }
        var opened = false
        if !cup.isDue {
            guard let due = nextCupLeagueRound, round >= due else { return }
            self.cup?.isDue = true
            opened = true
        }
        // 열려 있는데 내 경기가 없으면(쉬는 라운드, 탈락, 구단을 옮겼다) 여기서 끝낸다.
        if pendingCupTie == nil { finishCupRound() } else if opened { post("컵대회 \(cup.roundName) 차례입니다.") }
    }

    // MARK: 경기 결과

    /// 내 컵 경기의 결과를 적는다.
    mutating func recordCupTie(home: TeamID, homeScore: Int, awayScore: Int, homeWon: Bool, shootout: Bool = false) {
        guard var cup, let index = cup.ties.firstIndex(where: { $0.home == home && !$0.isPlayed }) else { return }
        cup.ties[index].homeScore = homeScore
        cup.ties[index].awayScore = awayScore
        cup.ties[index].winner = homeWon ? home : cup.ties[index].away
        cup.ties[index].shootout = shootout
        self.cup = cup
    }

    /// 이번 라운드의 남은 경기를 화면 없이 치르고, 다음 라운드를 추첨한다.
    mutating func finishCupRound() {
        guard var cup, !cup.isFinished else { return }
        for index in cup.ties.indices where !cup.ties[index].isPlayed {
            let tie = cup.ties[index]
            ensurePlayable(tie.home)
            ensurePlayable(tie.away)
            let tier = min(teams[tie.home].tier, teams[tie.away].tier)
            if let result = playQuietKnockout(home: tie.home, away: tie.away, kind: .cup, tier: tier, seed: rng.next()) {
                cup.ties[index].homeScore = result.homeScore
                cup.ties[index].awayScore = result.awayScore
                cup.ties[index].shootout = result.shootout
                cup.ties[index].winner = result.homeWon ? tie.home : tie.away
            }
            // 경기를 만들 수 없으면(선수가 모자란 구단) 강한 쪽이 올라간다.
            if cup.ties[index].winner == nil {
                cup.ties[index].winner = strength(of: tie.home) >= strength(of: tie.away) ? tie.home : tie.away
            }
        }

        let winners = cup.byes + cup.ties.compactMap(\.winner)
        cup.history.append(cup.ties)
        cup.byes = []
        cup.isDue = false
        cup.roundIndex += 1
        if winners.count <= 1 {
            cup.ties = []
            cup.champion = winners.first
            self.cup = cup
            if let champion = cup.champion {
                post("\(teams[champion].name), \(season)시즌 컵대회 우승!")
                if isCareer { settleCareerCupFinal(champion: champion, final: cup.history.last?.first) }
            }
        } else {
            cup.ties = drawCup(winners)
            self.cup = cup
            if let next = self.cup, let mine = next.ties.first(where: { $0.involves(userTeamID) }) {
                let opponent = teams[mine.opponent(of: userTeamID)]
                post("컵대회 \(next.roundName) 추첨: \(opponent.name) (\(opponent.tier.rawValue)부)과(와) 만납니다.")
            }
        }
    }

    /// 정규시즌이 끝날 때 대회가 아직 남아 있으면(예전 저장 파일로 시즌 도중에 대회가 생긴 경우) 끝까지 치른다.
    mutating func finishCupQuietly() {
        var guardCount = 0
        while let cup, !cup.isFinished, guardCount < 10 {
            guardCount += 1
            finishCupRound()
        }
    }

    // MARK: 선수 모드 보상

    /// 내 컵 경기 뒤: 올라가면 명성이 오르고, 윗 리그 구단을 잡으면 더 오른다.
    mutating func settleCareerCupTie(won: Bool, opponent: TeamID, roundName: String) -> [String] {
        guard var career, !career.retired else { return [] }
        var lines: [String] = []
        if won {
            var gain = Balance.cupWinFame
            let upset = teams[opponent].tier < userTier
            if upset { gain += Balance.cupUpsetFame * Double(userTier.rawValue - teams[opponent].tier.rawValue) }
            career.fame = min(100, career.fame + gain)
            lines.append(upset
                ? "컵대회 \(roundName): 윗 리그의 \(teams[opponent].name)을(를) 잡았습니다! 명성 +\(Int(gain.rounded()))"
                : "컵대회 \(roundName) 통과. 명성 +\(Int(gain.rounded()))")
        } else {
            lines.append("컵대회 \(roundName)에서 탈락했습니다.")
        }
        self.career = career
        return lines
    }

    /// 결승이 끝났을 때: 내 구단이 우승하면 수상 경력에 남고 명성과 감독 신뢰가 오른다.
    mutating func settleCareerCupFinal(champion: TeamID, final: CupTie?) {
        guard var career, !career.retired, !career.isFreeAgent else { return }
        if champion == userTeamID {
            career.fame = min(100, career.fame + Balance.cupChampionFame)
            career.trust = min(100, career.trust + Balance.cupChampionTrust)
            career.awards.append("\(season)시즌 컵대회 우승")
            post("컵대회 우승! 명성 +\(Int(Balance.cupChampionFame)), 감독 신뢰 +\(Int(Balance.cupChampionTrust)).")
        } else if final?.involves(userTeamID) == true {
            career.fame = min(100, career.fame + Balance.cupRunnerUpFame)
            career.awards.append("\(season)시즌 컵대회 준우승")
            post("컵대회 준우승. 명성 +\(Int(Balance.cupRunnerUpFame)).")
        }
        self.career = career
    }
}
