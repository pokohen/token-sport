import Foundation

/// 1:1 대전의 팀 경기 (또는 개인 대회의 한 판): 세트 여럿을 먼저 과반 이기는 쪽이 이긴다.
/// 정규 시즌은 3전 2선승, 플레이오프와 개인 대회 결승은 5전 3선승이다.
///
/// 세트 배정 (→ docs/10-esports.md "팀 리그"): `lineup[0]`이 에이스다. 일반 세트는 `lineup`을 차례로 쓰고,
/// 마지막 세트(1 : 1, 2 : 2)까지 가면 에이스가 에이스 결정전에 다시 나간다.
/// `step()`을 부를 때마다 세트 하나의 15초가 흐른다. 세트와 세트 사이에는 한 틱을 쉬며 다음 세트를 알린다.
public struct DuelMatch: Codable, Equatable, Sendable {
    public struct Side: Codable, Equatable, Sendable {
        /// 팀 경기면 팀, 개인 대회면 nil.
        public var teamID: TeamID?
        public var name: String
        /// 세트에 나갈 선수 (맨 앞이 에이스).
        public var lineup: [PlayerID]
        public var players: [PlayerID: DuelPlayer]
        public internal(set) var sets = 0

        public init(teamID: TeamID?, name: String, lineup: [PlayerID], players: [PlayerID: DuelPlayer]) {
            self.teamID = teamID
            self.name = name
            self.lineup = lineup
            self.players = players
        }
    }

    /// 세트에서 한 선수가 남긴 것 (평점에 쓴다).
    public struct SetStats: Codable, Equatable, Sendable {
        public var playerID: PlayerID
        public var name: String
        public var race: DuelRace
        public var overall: Double
        public var armyKilled: Double
        public var armyLost: Double
        public var workersKilled: Double
        public var workersLost: Double
        /// 세트 중 가장 크게 밀렸던 정도.
        public var worstDeficit: Double
    }

    /// 끝난 세트 하나.
    public struct SetRecord: Codable, Equatable, Sendable {
        public var number: Int
        public var map: String
        public var stakes: DuelStakes
        /// 에이스 결정전이었는지.
        public var decider: Bool
        public var home: SetStats
        public var away: SetStats
        public var homeWon: Bool
        public var ending: DuelSet.Ending
        /// 끝난 틱 (15초 단위).
        public var ticks: Int

        public var isAce: Bool { decider }

        /// 이 선수가 나온 세트면 (이겼는지, 내 기록, 상대 기록).
        public func entry(for playerID: PlayerID) -> (won: Bool, me: SetStats, them: SetStats)? {
            if home.playerID == playerID { return (homeWon, home, away) }
            if away.playerID == playerID { return (!homeWon, away, home) }
            return nil
        }
    }

    public internal(set) var home: Side
    public internal(set) var away: Side
    public let bestOf: Int
    /// 결승: 모든 세트가 큰 경기다 (멘탈이 더 크게 작용한다).
    public let isFinal: Bool
    public internal(set) var current: DuelSet?
    public internal(set) var records: [SetRecord] = []
    public internal(set) var isFinished = false
    public internal(set) var log: [MatchEvent] = []
    var rng: SeededRNG
    static let logLimit = 80

    public init(home: Side, away: Side, bestOf: Int, isFinal: Bool = false, seed: UInt64) {
        self.home = home
        self.away = away
        self.bestOf = bestOf
        self.isFinal = isFinal
        self.rng = SeededRNG(seed: seed)
    }

    // MARK: 읽기

    public var needed: Int { bestOf / 2 + 1 }
    public var homeWon: Bool { home.sets > away.sets }
    /// 다음 세트가 에이스 결정전인지.
    public var isDecider: Bool { home.sets == needed - 1 && away.sets == needed - 1 }

    /// 이 세트에 나가는 선수: 결정전이면 에이스, 아니면 출전 순서대로.
    static func pick(_ side: Side, setIndex: Int, decider: Bool) -> PlayerID {
        decider || side.lineup.count == 1 ? side.lineup[0] : side.lineup[setIndex % side.lineup.count]
    }

    /// 지금 세트에 나와 있는 두 선수 (세트 사이면 nil).
    public var currentPlayers: (home: PlayerID, away: PlayerID)? {
        guard current != nil else { return nil }
        let decider = isDecider
        return (Self.pick(home, setIndex: records.count, decider: decider),
                Self.pick(away, setIndex: records.count, decider: decider))
    }

    /// "세트 1 : 0 · 2세트 4:30 · 확장 3 : 2 · 병력 120 : 85".
    public var scoreboard: String {
        var text = "세트 \(home.sets) : \(away.sets)"
        if let current { text += " · \(records.count + 1)세트 \(current.clockLabel) · \(current.scoreboard)" }
        return text
    }

    /// 이 선수가 이 경기에서 나온 세트들.
    public func sets(of playerID: PlayerID) -> [SetRecord] {
        records.filter { $0.entry(for: playerID) != nil }
    }

    // MARK: 진행

    @discardableResult
    public mutating func step() -> [MatchEvent] {
        guard !isFinished else { return [] }
        var events: [MatchEvent] = []
        if var set = current {
            // 세트 안의 "GG"는 경기 끝이 아니라 세트 끝이다.
            events += set.step().map { $0.kind == .end ? MatchEvent(.score, $0.text) : $0 }
            current = set
            if set.isFinished { finishSet(set, &events) }
        } else {
            startSet(&events)
        }
        log.append(contentsOf: events)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        return events
    }

    public mutating func runToEnd() {
        while !isFinished { step() }
    }

    mutating func startSet(_ events: inout [MatchEvent]) {
        let decider = isDecider
        let index = records.count
        let homeID = Self.pick(home, setIndex: index, decider: decider)
        let awayID = Self.pick(away, setIndex: index, decider: decider)
        guard let first = home.players[homeID], let second = away.players[awayID] else {
            isFinished = true
            return
        }
        let stakes: DuelStakes = isFinal ? .final : decider ? .ace : .regular
        current = DuelSet(first: first, second: second, map: rng.pick(DuelMap.pool), stakes: stakes, seed: rng.next())
        let title = decider ? "\(index + 1)세트, 에이스 결정전" : "\(index + 1)세트"
        events.append(MatchEvent(.inning, "\(title): \(first.name)(\(first.race.label)) 대 \(second.name)(\(second.race.label))"))
    }

    mutating func finishSet(_ set: DuelSet, _ events: inout [MatchEvent]) {
        guard let winner = set.winner, let ending = set.ending else { return }
        let decider = isDecider
        let index = records.count
        let ids = [Self.pick(home, setIndex: index, decider: decider), Self.pick(away, setIndex: index, decider: decider)]
        func stats(_ side: Int) -> SetStats {
            let duel = set.sides[side]
            return SetStats(
                playerID: ids[side], name: duel.player.name, race: duel.player.race, overall: duel.player.overall,
                armyKilled: duel.armyKilled, armyLost: duel.armyLost,
                workersKilled: duel.workersKilled, workersLost: duel.workersLost, worstDeficit: duel.worstDeficit)
        }
        records.append(SetRecord(
            number: index + 1, map: set.map.name, stakes: set.stakes, decider: decider,
            home: stats(0), away: stats(1), homeWon: winner == 0, ending: ending, ticks: set.tick))
        if winner == 0 { home.sets += 1 } else { away.sets += 1 }
        current = nil
        let name = winner == 0 ? home.name : away.name
        events.append(MatchEvent(
            .score, "\(index + 1)세트 \(set.sides[winner].player.name) 승리 · \(name) 세트 \(home.sets) : \(away.sets)"))
        if home.sets >= needed || away.sets >= needed {
            isFinished = true
            let won = homeWon ? home.name : away.name
            events.append(MatchEvent(.end, "\(won), 세트 \(max(home.sets, away.sets)) : \(min(home.sets, away.sets))로 승리!"))
        }
    }
}

/// 1:1 대전 선수의 시즌 기록.
public struct DuelLine: Codable, Equatable, Sendable {
    /// 세트에 한 번이라도 나온 팀 경기 수.
    public var games = 0
    public var setWins = 0, setLosses = 0
    public var aceWins = 0, aceLosses = 0
    /// 상대 종족별 [승, 패] (키: 종족 rawValue).
    public var versus: [String: [Int]] = [:]

    public init() {}

    public var sets: Int { setWins + setLosses }
    public var winRate: Double { sets == 0 ? 0 : Double(setWins) / Double(sets) }

    /// "대 에일리언 12승 5패".
    public func versusText(_ race: DuelRace) -> String {
        let record = versus[race.rawValue] ?? [0, 0]
        return "대 \(race.label) \(record[0])승 \(record[1])패"
    }

    mutating func add(_ record: DuelMatch.SetRecord, playerID: PlayerID) {
        guard let entry = record.entry(for: playerID) else { return }
        if entry.won { setWins += 1 } else { setLosses += 1 }
        if record.isAce { if entry.won { aceWins += 1 } else { aceLosses += 1 } }
        var pair = versus[entry.them.race.rawValue] ?? [0, 0]
        pair[entry.won ? 0 : 1] += 1
        versus[entry.them.race.rawValue] = pair
    }

    public static func += (lhs: inout DuelLine, rhs: DuelLine) {
        lhs.games += rhs.games
        lhs.setWins += rhs.setWins
        lhs.setLosses += rhs.setLosses
        lhs.aceWins += rhs.aceWins
        lhs.aceLosses += rhs.aceLosses
        for (key, pair) in rhs.versus {
            let mine = lhs.versus[key] ?? [0, 0]
            lhs.versus[key] = [mine[0] + pair[0], mine[1] + pair[1]]
        }
    }
}
