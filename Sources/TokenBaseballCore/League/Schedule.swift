import Foundation

public struct Fixture: Codable, Equatable, Sendable {
    public var home: TeamID
    public var away: TeamID

    public func involves(_ team: TeamID) -> Bool { home == team || away == team }
    public func opponent(of team: TeamID) -> TeamID { home == team ? away : home }
}

public enum ScheduleBuilder {
    /// 더블 라운드 로빈을 `repeats`번: 모든 팀과 홈·원정을 `repeats`경기씩.
    /// 10팀이 두 번 돌면 36라운드, 20팀이 한 번 돌면 38라운드이고, 같은 상대와 연속으로 붙지 않는다.
    public static func build(teams: [TeamID], repeats: Int = 2, _ rng: inout SeededRNG) -> [[Fixture]] {
        precondition(teams.count % 2 == 0 && teams.count >= 4)
        let order = rng.shuffled(teams)
        let count = order.count
        var firstLeg: [[Fixture]] = []

        // 원형 배치: 첫 팀은 고정하고 나머지를 한 칸씩 돌린다.
        var rotating = Array(order.dropFirst())
        for round in 0..<(count - 1) {
            let circle = [order[0]] + rotating
            var fixtures: [Fixture] = []
            for pair in 0..<(count / 2) {
                let a = circle[pair]
                let b = circle[count - 1 - pair]
                // 홈·원정이 한쪽으로 몰리지 않게 라운드마다 번갈아 준다.
                let aHome = pair == 0 ? round % 2 == 0 : (round + pair) % 2 == 0
                fixtures.append(aHome ? Fixture(home: a, away: b) : Fixture(home: b, away: a))
            }
            firstLeg.append(fixtures)
            rotating.insert(rotating.removeLast(), at: 0)
        }

        let secondLeg = firstLeg.map { $0.map { Fixture(home: $0.away, away: $0.home) } }
        let half = firstLeg + secondLeg
        return Array(repeating: half, count: max(1, repeats)).flatMap { $0 }
    }
}

/// 순위표의 한 줄.
public struct StandingRow: Codable, Equatable, Sendable {
    public var teamID: TeamID
    public var wins = 0, draws = 0, losses = 0
    public var runsFor = 0, runsAgainst = 0
    /// 팀 타율·평균자책점 계산용.
    public var atBats = 0, hits = 0, earnedRuns = 0, pitchingOuts = 0
    /// 상대 전적: 상대 팀별 승수.
    public var winsAgainst: [TeamID: Int] = [:]

    public init(teamID: TeamID) { self.teamID = teamID }

    public var games: Int { wins + draws + losses }
    /// 승률 = 승 / (승 + 패). 무승부는 뺀다.
    public var winRate: Double {
        wins + losses == 0 ? 0 : Double(wins) / Double(wins + losses)
    }
    /// 축구: 승 3점, 무 1점.
    public var points: Int { wins * 3 + draws }
    public var goalDifference: Int { runsFor - runsAgainst }
    public var battingAverage: Double { atBats == 0 ? 0 : Double(hits) / Double(atBats) }
    public var era: Double { pitchingOuts == 0 ? 0 : Double(earnedRuns) * 27 / Double(pitchingOuts) }
}

public enum Standings {
    /// KBO 방식: 승률 → 동률 팀끼리의 상대 전적 → 다득점.
    public static func ranked(_ rows: [StandingRow], sport: Sport) -> [StandingRow] {
        sport.ranksByPoints ? rankedByPoints(rows) : ranked(rows)
    }

    /// 축구: 승점 → 골득실 → 다득점 → 동률 팀끼리의 상대 전적.
    public static func rankedByPoints(_ rows: [StandingRow]) -> [StandingRow] {
        func key(_ row: StandingRow) -> [Int] { [row.points, row.goalDifference, row.runsFor] }
        let groups = Dictionary(grouping: rows, by: key)
        func headToHead(_ row: StandingRow) -> Int {
            (groups[key(row)] ?? []).reduce(0) { $0 + (row.winsAgainst[$1.teamID] ?? 0) }
        }
        return rows.sorted { a, b in
            let ka = key(a), kb = key(b)
            if ka != kb { return kb.lexicographicallyPrecedes(ka) }
            return (headToHead(a), -a.teamID) > (headToHead(b), -b.teamID)
        }
    }

    public static func ranked(_ rows: [StandingRow]) -> [StandingRow] {
        let byRate = rows.sorted { ($0.winRate, -$0.teamID) > ($1.winRate, -$1.teamID) }
        var result: [StandingRow] = []
        var index = 0
        while index < byRate.count {
            var end = index + 1
            while end < byRate.count, abs(byRate[end].winRate - byRate[index].winRate) < 1e-9 { end += 1 }
            var group = Array(byRate[index..<end])
            if group.count > 1 {
                let ids = group.map(\.teamID)
                func headToHead(_ row: StandingRow) -> Int {
                    ids.reduce(0) { $0 + (row.winsAgainst[$1] ?? 0) }
                }
                group.sort {
                    (headToHead($0), $0.runsFor, -$0.teamID) > (headToHead($1), $1.runsFor, -$1.teamID)
                }
            }
            result += group
            index = end
        }
        return result
    }
}
