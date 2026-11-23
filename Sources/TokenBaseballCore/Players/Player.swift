import Foundation

public enum Position: String, Codable, CaseIterable, Sendable {
    case starter = "SP", reliever = "RP", closer = "CL"
    case catcher = "C", first = "1B", second = "2B", third = "3B", shortstop = "SS"
    case left = "LF", center = "CF", right = "RF", designated = "DH"
    // 축구
    case goalkeeper = "GK", defender = "DF", midfielder = "MF", forward = "FW"
    // 농구 ("C"는 포수가 쓰고 있어서 센터는 "CE"다)
    case pointGuard = "PG", shootingGuard = "SG", smallForward = "SF", powerForward = "PF", center5 = "CE"

    public var sport: Sport {
        switch self {
        case .goalkeeper, .defender, .midfielder, .forward: .football
        case .pointGuard, .shootingGuard, .smallForward, .powerForward, .center5: .basketball
        case .starter, .reliever, .closer, .catcher, .first, .second, .third, .shortstop,
             .left, .center, .right, .designated: .baseball
        }
    }

    public var isPitcher: Bool { self == .starter || self == .reliever || self == .closer }

    public var label: String {
        switch self {
        case .starter: "선발"
        case .reliever: "불펜"
        case .closer: "마무리"
        case .catcher: "포수"
        case .first: "1루수"
        case .second: "2루수"
        case .third: "3루수"
        case .shortstop: "유격수"
        case .left: "좌익수"
        case .center: "중견수"
        case .right: "우익수"
        case .designated: "지명타자"
        case .goalkeeper: "골키퍼"
        case .defender: "수비수"
        case .midfielder: "미드필더"
        case .forward: "공격수"
        case .pointGuard: "포인트 가드"
        case .shootingGuard: "슈팅 가드"
        case .smallForward: "스몰 포워드"
        case .powerForward: "파워 포워드"
        case .center5: "센터"
        }
    }

    /// 수비에 서는 여덟 자리.
    public static let fieldPositions: [Position] = [
        .catcher, .first, .second, .third, .shortstop, .left, .center, .right,
    ]
    public static let infield: [Position] = [.first, .second, .third, .shortstop]
    public static let outfield: [Position] = [.left, .center, .right]
    /// 축구의 네 포지션.
    public static let football: [Position] = [.goalkeeper, .defender, .midfielder, .forward]
    /// 농구의 다섯 포지션.
    public static let basketball: [Position] = [.pointGuard, .shootingGuard, .smallForward, .powerForward, .center5]

    public static func all(for sport: Sport) -> [Position] {
        allCases.filter { $0.sport == sport }
    }
}

public enum Hand: String, Codable, Sendable {
    case right = "우", left = "좌"
}

/// 세부 능력치 (1~99). 성장이 조금씩 쌓이므로 소수로 갖고 있고, 화면에는 반올림해 보여준다.
public struct Attributes: Codable, Equatable, Sendable {
    public var contact = 1.0
    public var power = 1.0
    public var eye = 1.0
    public var speed = 1.0
    public var fielding = 1.0
    public var arm = 1.0
    public var stuff = 1.0
    public var control = 1.0
    public var breaking = 1.0
    public var stamina = 1.0
    // 축구 (스피드와 체력은 위의 것을 같이 쓴다)
    public var shooting = 1.0
    public var passing = 1.0
    public var dribbling = 1.0
    public var tackling = 1.0
    public var physical = 1.0
    public var keeping = 1.0
    // 농구 (슛·패스·드리블·수비·스피드·피지컬·체력은 위의 것을 같이 쓴다)
    public var three = 1.0
    public var rebounding = 1.0

    public init() {}

    /// 예전 저장 파일에는 축구 능력치가 없으므로, 없는 값은 기본값으로 둔다.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: Key.self)
        for key in Key.allCases {
            if let value = try container.decodeIfPresent(Double.self, forKey: key) { self[key] = value }
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: Key.self)
        for key in Key.allCases { try container.encode(self[key], forKey: key) }
    }

    public enum Key: String, CaseIterable, Codable, CodingKey, Sendable {
        case contact, power, eye, speed, fielding, arm, stuff, control, breaking, stamina
        case shooting, passing, dribbling, tackling, physical, keeping
        case three, rebounding

        /// 종목별로 쓰는 능력치. 야구는 예전 순서 그대로다 (선수를 만들 때 난수를 이 순서로 쓴다).
        public static func all(for sport: Sport) -> [Key] {
            switch sport {
            case .baseball: [.contact, .power, .eye, .speed, .fielding, .arm, .stuff, .control, .breaking, .stamina]
            case .football: [.shooting, .passing, .dribbling, .tackling, .speed, .physical, .keeping, .stamina]
            case .basketball:
                [.shooting, .three, .passing, .dribbling, .tackling, .rebounding, .speed, .physical, .stamina]
            }
        }

        public var label: String {
            switch self {
            case .contact: "컨택"
            case .power: "파워"
            case .eye: "선구안"
            case .speed: "주력"
            case .fielding: "수비"
            case .arm: "어깨"
            case .stuff: "구위"
            case .control: "제구"
            case .breaking: "변화구"
            case .stamina: "체력"
            case .shooting: "슈팅"
            case .passing: "패스"
            case .dribbling: "드리블"
            case .tackling: "수비"
            case .physical: "피지컬"
            case .keeping: "골키핑"
            case .three: "3점슛"
            case .rebounding: "리바운드"
            }
        }
    }

    public subscript(key: Key) -> Double {
        get {
            switch key {
            case .contact: contact
            case .power: power
            case .eye: eye
            case .speed: speed
            case .fielding: fielding
            case .arm: arm
            case .stuff: stuff
            case .control: control
            case .breaking: breaking
            case .stamina: stamina
            case .shooting: shooting
            case .passing: passing
            case .dribbling: dribbling
            case .tackling: tackling
            case .physical: physical
            case .keeping: keeping
            case .three: three
            case .rebounding: rebounding
            }
        }
        set {
            switch key {
            case .contact: contact = newValue
            case .power: power = newValue
            case .eye: eye = newValue
            case .speed: speed = newValue
            case .fielding: fielding = newValue
            case .arm: arm = newValue
            case .stuff: stuff = newValue
            case .control: control = newValue
            case .breaking: breaking = newValue
            case .stamina: stamina = newValue
            case .shooting: shooting = newValue
            case .passing: passing = newValue
            case .dribbling: dribbling = newValue
            case .tackling: tackling = newValue
            case .physical: physical = newValue
            case .keeping: keeping = newValue
            case .three: three = newValue
            case .rebounding: rebounding = newValue
            }
        }
    }

    /// 포지션별 능력(CA) 가중치. 합은 1이다.
    public static func weights(for position: Position) -> [(Key, Double)] {
        switch position {
        case .starter:
            [(.stuff, 0.32), (.control, 0.28), (.breaking, 0.22), (.stamina, 0.18)]
        case .reliever, .closer:
            [(.stuff, 0.40), (.control, 0.28), (.breaking, 0.27), (.stamina, 0.05)]
        case .catcher:
            [(.contact, 0.24), (.power, 0.18), (.eye, 0.13), (.speed, 0.05), (.fielding, 0.24), (.arm, 0.16)]
        case .designated:
            [(.contact, 0.36), (.power, 0.34), (.eye, 0.22), (.speed, 0.08)]
        case .goalkeeper:
            [(.keeping, 0.70), (.physical, 0.15), (.passing, 0.10), (.speed, 0.05)]
        case .defender:
            [(.tackling, 0.40), (.physical, 0.20), (.speed, 0.15), (.passing, 0.15), (.stamina, 0.10)]
        case .midfielder:
            [(.passing, 0.35), (.dribbling, 0.20), (.tackling, 0.15), (.stamina, 0.15), (.shooting, 0.10), (.speed, 0.05)]
        case .forward:
            [(.shooting, 0.38), (.dribbling, 0.20), (.speed, 0.17), (.physical, 0.10), (.passing, 0.08), (.stamina, 0.07)]
        case .pointGuard:
            [(.passing, 0.30), (.dribbling, 0.22), (.three, 0.15), (.speed, 0.13), (.shooting, 0.10), (.tackling, 0.10)]
        case .shootingGuard:
            [(.three, 0.28), (.shooting, 0.25), (.dribbling, 0.15), (.tackling, 0.12), (.speed, 0.10), (.passing, 0.10)]
        case .smallForward:
            [(.shooting, 0.25), (.three, 0.18), (.tackling, 0.17), (.physical, 0.15), (.speed, 0.15), (.rebounding, 0.10)]
        case .powerForward:
            [(.rebounding, 0.25), (.shooting, 0.23), (.physical, 0.22), (.tackling, 0.20), (.three, 0.05), (.stamina, 0.05)]
        case .center5:
            [(.rebounding, 0.30), (.physical, 0.25), (.tackling, 0.22), (.shooting, 0.18), (.stamina, 0.05)]
        case .first, .second, .third, .shortstop, .left, .center, .right:
            [(.contact, 0.28), (.power, 0.22), (.eye, 0.15), (.speed, 0.10), (.fielding, 0.17), (.arm, 0.08)]
        }
    }
}

public struct Contract: Codable, Equatable, Sendable {
    /// 시즌 연봉. 경기마다 36분의 1씩 낸다.
    public var salary: Int
    /// 남은 시즌 수. 1이면 이번 시즌이 마지막이다.
    public var seasonsLeft: Int
    /// 강등 조항: 팀이 강등되면 다른 구단이 정해진 이적료로 데려갈 수 있다.
    public var relegationClause: Bool

    public init(salary: Int, seasonsLeft: Int, relegationClause: Bool = false) {
        self.salary = salary
        self.seasonsLeft = seasonsLeft
        self.relegationClause = relegationClause
    }
}

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

/// 선수 특성. 경기 시뮬레이션의 해당 상황에서 작은 보정을 준다.
public enum Trait: String, Codable, CaseIterable, Sendable {
    case clutch = "찬스에 강함"
    case slowStarter = "첫 타석 약함"
    case leftyKiller = "왼손 투수 킬러"
    case ironGlove = "철벽 수비"
    case coolHead = "위기에 강함"
    // 축구
    case ironLungs = "강철 체력"
    case setPiece = "프리킥 장인"

    public var forPitcher: Bool { self == .coolHead }

    /// 이 포지션의 선수가 가질 수 있는 특성. 야구 쪽 순서는 예전 그대로다.
    public static func pool(for position: Position) -> [Trait] {
        switch position {
        case .goalkeeper: [.coolHead]
        case .defender, .midfielder, .forward: [.clutch, .ironGlove, .ironLungs, .setPiece]
        case .pointGuard, .shootingGuard, .smallForward, .powerForward, .center5: [.clutch, .ironLungs]
        default:
            [.clutch, .slowStarter, .leftyKiller, .ironGlove, .coolHead]
                .filter { $0.forPitcher == position.isPitcher || $0 == .ironGlove && !position.isPitcher }
        }
    }
}

public typealias PlayerID = Int
public typealias TeamID = Int

public struct Player: Codable, Identifiable, Equatable, Sendable {
    public let id: PlayerID
    public var name: String
    public var age: Int
    public var position: Position
    public var bats: Hand
    public var throwsHand: Hand
    public var attributes: Attributes
    /// 잠재력 (PA). 숨겨진 값이고 화면에는 스카우트 별로만 보인다.
    public var potential: Double
    /// 스카우트가 잠재력을 잘못 보는 방향과 크기 (표준편차 단위).
    public var scoutBias: Double
    public var contract: Contract
    public var teamID: TeamID?
    /// 출신 한 줄 (예: "○○동 치킨집 사장").
    public var origin: String
    public var traits: [Trait]
    public var isForeign: Bool
    /// 지금 팀에 들어온 시즌과 그때 팀의 리그. 프랜차이즈 스타 판정에 쓴다.
    public var joinedSeason: Int
    public var joinedTier: Int
    public var isFranchiseStar: Bool
    /// 이번 시즌 기록.
    public var batting: BattingLine
    public var pitching: PitchingLine
    /// 축구 선수의 이번 시즌 기록. 야구 선수는 nil.
    public var football: FootballLine? = nil
    /// 농구 선수의 이번 시즌 기록. 다른 종목 선수는 nil.
    public var basketball: BasketballLine? = nil
    /// 마지막으로 선발 등판했을 때의 팀 경기 번호.
    public var lastStartGame: Int
    /// 시즌을 시작할 때의 능력 (연봉 인상 계산용).
    public var abilityAtSeasonStart: Double
    /// 직전 경기에서 활약해 "컨디션 좋음" 상태인지.
    public var isHot: Bool
    /// 마지막으로 구원 등판한 팀 경기 번호와 그때 던진 공 수 (불펜 휴식 계산용). 예전 저장 파일에는 없다.
    public var lastReliefGame: Int? = nil
    public var lastReliefPitches: Int? = nil
    /// 연달아 구원 등판한 경기 수.
    public var reliefStreak: Int? = nil
    /// 축구: 남은 출장 정지 경기 수.
    public var suspendedMatches: Int? = nil

    /// 이 불펜 투수가 다음 팀 경기(번호 `game`)에 쉬어야 하는지: 직전 경기에 25구 넘게 던졌거나 이틀 연속 나왔을 때.
    public func needsReliefRest(game: Int) -> Bool {
        guard let last = lastReliefGame, last == game - 1 else { return false }
        return (lastReliefPitches ?? 0) >= 25 || (reliefStreak ?? 0) >= 2
    }

    public var isPitcher: Bool { position.isPitcher }

    /// 능력 (CA): 세부 능력치를 포지션별 가중치로 합친 값.
    public var ability: Double {
        Attributes.weights(for: position).reduce(0) { $0 + attributes[$1.0] * $1.1 }
    }

    /// F~S 등급.
    public var grade: String { Player.grade(for: ability) }

    public static func grade(for ability: Double) -> String {
        switch ability {
        case ..<20: "F"
        case ..<30: "E"
        case ..<40: "D"
        case ..<50: "C"
        case ..<60: "B"
        case ..<75: "A"
        default: "S"
        }
    }

    /// 스카우트 평가 별 (1~5). 스카우트 시설 레벨이 높을수록 실제 잠재력에 가깝다.
    public func scoutStars(scoutLevel: Int) -> Int {
        let sigma = max(2.0, 12.0 - 2.0 * Double(scoutLevel))
        let seen = potential + scoutBias * sigma
        switch seen {
        case ..<30: return 1
        case ..<45: return 2
        case ..<60: return 3
        case ..<75: return 4
        default: return 5
        }
    }

    public var isExpiring: Bool { contract.seasonsLeft <= 1 }
}
