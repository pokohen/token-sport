import Foundation

// 선수의 시즌 기록. 종목마다 하나씩 있고, 경기 중에는 그 경기의 기록으로도 쓴다.

public struct BattingLine: Codable, Equatable, Sendable {
    public var games = 0, plateAppearances = 0, atBats = 0, hits = 0
    public var doubles = 0, triples = 0, homeRuns = 0
    public var runsBattedIn = 0, runs = 0, walks = 0, strikeouts = 0, steals = 0

    public init() {}

    public var average: Double { atBats == 0 ? 0 : Double(hits) / Double(atBats) }
    public var onBase: Double {
        let denominator = atBats + walks
        return denominator == 0 ? 0 : Double(hits + walks) / Double(denominator)
    }
    public var totalBases: Int { hits + doubles + 2 * triples + 3 * homeRuns }
    public var slugging: Double { atBats == 0 ? 0 : Double(totalBases) / Double(atBats) }
    public var ops: Double { onBase + slugging }

    public static func += (lhs: inout BattingLine, rhs: BattingLine) {
        lhs.games += rhs.games
        lhs.plateAppearances += rhs.plateAppearances
        lhs.atBats += rhs.atBats
        lhs.hits += rhs.hits
        lhs.doubles += rhs.doubles
        lhs.triples += rhs.triples
        lhs.homeRuns += rhs.homeRuns
        lhs.runsBattedIn += rhs.runsBattedIn
        lhs.runs += rhs.runs
        lhs.walks += rhs.walks
        lhs.strikeouts += rhs.strikeouts
        lhs.steals += rhs.steals
    }
}

public struct PitchingLine: Codable, Equatable, Sendable {
    public var games = 0, starts = 0, wins = 0, losses = 0, saves = 0
    public var outs = 0, hits = 0, runs = 0, earnedRuns = 0
    public var walks = 0, strikeouts = 0, homeRuns = 0, pitches = 0

    public init() {}

    public var era: Double { outs == 0 ? 0 : Double(earnedRuns) * 27 / Double(outs) }
    /// "5.2" 같은 이닝 표기.
    public var innings: String { "\(outs / 3).\(outs % 3)" }

    public static func += (lhs: inout PitchingLine, rhs: PitchingLine) {
        lhs.games += rhs.games
        lhs.starts += rhs.starts
        lhs.wins += rhs.wins
        lhs.losses += rhs.losses
        lhs.saves += rhs.saves
        lhs.outs += rhs.outs
        lhs.hits += rhs.hits
        lhs.runs += rhs.runs
        lhs.earnedRuns += rhs.earnedRuns
        lhs.walks += rhs.walks
        lhs.strikeouts += rhs.strikeouts
        lhs.homeRuns += rhs.homeRuns
        lhs.pitches += rhs.pitches
    }
}

/// 축구 선수의 시즌 기록 (경기 중에는 그 경기의 기록).
public struct FootballLine: Codable, Equatable, Sendable {
    public var games = 0, goals = 0, assists = 0
    public var shots = 0, shotsOnTarget = 0
    public var yellowCards = 0, redCards = 0
    /// 골키퍼 기록.
    public var saves = 0, conceded = 0, cleanSheets = 0

    public init() {}

    public var points: Int { goals + assists }

    public static func += (lhs: inout FootballLine, rhs: FootballLine) {
        lhs.games += rhs.games
        lhs.goals += rhs.goals
        lhs.assists += rhs.assists
        lhs.shots += rhs.shots
        lhs.shotsOnTarget += rhs.shotsOnTarget
        lhs.yellowCards += rhs.yellowCards
        lhs.redCards += rhs.redCards
        lhs.saves += rhs.saves
        lhs.conceded += rhs.conceded
        lhs.cleanSheets += rhs.cleanSheets
    }
}

/// 농구 선수의 시즌 기록 (경기 중에는 그 경기의 기록).
public struct BasketballLine: Codable, Equatable, Sendable {
    public var games = 0, starts = 0
    /// 뛴 시간(초).
    public var seconds = 0
    public var points = 0, rebounds = 0, assists = 0, steals = 0, blocks = 0, turnovers = 0, fouls = 0
    public var fieldGoalsMade = 0, fieldGoalsAttempted = 0
    public var threesMade = 0, threesAttempted = 0
    public var freeThrowsMade = 0, freeThrowsAttempted = 0

    public init() {}

    public var minutes: Int { seconds / 60 }
    public var pointsPerGame: Double { games == 0 ? 0 : Double(points) / Double(games) }
    public var reboundsPerGame: Double { games == 0 ? 0 : Double(rebounds) / Double(games) }
    public var assistsPerGame: Double { games == 0 ? 0 : Double(assists) / Double(games) }
    public var minutesPerGame: Double { games == 0 ? 0 : Double(seconds) / 60 / Double(games) }
    public var fieldGoalRate: Double {
        fieldGoalsAttempted == 0 ? 0 : Double(fieldGoalsMade) / Double(fieldGoalsAttempted)
    }
    public var threeRate: Double { threesAttempted == 0 ? 0 : Double(threesMade) / Double(threesAttempted) }
    /// 두 자릿수 기록이 둘 이상이면 더블더블 (득점, 리바운드, 어시스트, 스틸, 블록 가운데).
    public var isDoubleDouble: Bool {
        [points, rebounds, assists, steals, blocks].filter { $0 >= 10 }.count >= 2
    }

    public static func += (lhs: inout BasketballLine, rhs: BasketballLine) {
        lhs.games += rhs.games
        lhs.starts += rhs.starts
        lhs.seconds += rhs.seconds
        lhs.points += rhs.points
        lhs.rebounds += rhs.rebounds
        lhs.assists += rhs.assists
        lhs.steals += rhs.steals
        lhs.blocks += rhs.blocks
        lhs.turnovers += rhs.turnovers
        lhs.fouls += rhs.fouls
        lhs.fieldGoalsMade += rhs.fieldGoalsMade
        lhs.fieldGoalsAttempted += rhs.fieldGoalsAttempted
        lhs.threesMade += rhs.threesMade
        lhs.threesAttempted += rhs.threesAttempted
        lhs.freeThrowsMade += rhs.freeThrowsMade
        lhs.freeThrowsAttempted += rhs.freeThrowsAttempted
    }
}
