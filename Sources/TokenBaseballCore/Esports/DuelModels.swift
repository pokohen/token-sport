import Foundation

// e스포츠 1:1 대전의 재료. 아직 선수 모드에 붙이지 않은 엔진 단계다 (→ docs/10-esports.md "만드는 순서" 2).
// 게임, 종족, 맵 이름은 모두 지어낸 것이다. 실제 게임의 고유 이름을 쓰지 않는다.

/// 세 종족. 처음에 고르고 바꿀 수 없다.
public enum DuelRace: String, Codable, CaseIterable, Sendable {
    case human, alien, protector

    public var label: String {
        switch self {
        case .human: "휴먼"
        case .alien: "에일리언"
        case .protector: "프로텍터"
        }
    }

    /// 수입 하나로 뽑는 병력의 양. 에일리언은 싸고 많이, 프로텍터는 비싸고 적게.
    var armyRate: Double {
        switch self {
        case .human: 1.0
        case .alien: 1.2
        case .protector: 0.8
        }
    }

    /// 병력 하나하나의 싸움 힘. 휴먼은 방어 시설과 기계 병력으로 늦게 강해진다.
    func fightStrength(tick: Int) -> Double {
        switch self {
        case .human: tick < 30 ? 0.95 : tick < 55 ? 1.02 : 1.1
        case .alien: 0.85
        case .protector: tick < 25 ? 1.3 : 1.4
        }
    }

    /// 종족마다 중요한 능력치 비중 (합 1).
    public var weights: DuelSkills {
        switch self {
        case .human: DuelSkills(control: 0.15, macro: 0.3, strategy: 0.15, judgment: 0.25, mental: 0.15)
        case .alien: DuelSkills(control: 0.3, macro: 0.3, strategy: 0.1, judgment: 0.15, mental: 0.15)
        case .protector: DuelSkills(control: 0.3, macro: 0.2, strategy: 0.25, judgment: 0.1, mental: 0.15)
        }
    }
}

/// 1:1 대전 선수의 능력치 다섯 가지 (0~99).
/// 선수 모드에 붙일 때 `Attributes`와 어떻게 합칠지는 다음 단계(세계 만들기)에서 정한다.
public struct DuelSkills: Codable, Equatable, Sendable {
    /// 병력 하나하나를 다루는 손. 교전에서 덜 잃고 더 잡는다.
    public var control: Double
    /// 일꾼, 확장, 생산을 쉬지 않고 돌리는 힘.
    public var macro: Double
    /// 빌드를 짜고 상대 빌드를 읽는 능력. 깜짝 빌드의 성공률.
    public var strategy: Double
    /// 정찰, 싸울 때와 물러날 때를 아는 능력.
    public var judgment: Double
    /// 지고 있을 때, 큰 경기에서 버티는 힘.
    public var mental: Double

    public init(control: Double, macro: Double, strategy: Double, judgment: Double, mental: Double) {
        self.control = control
        self.macro = macro
        self.strategy = strategy
        self.judgment = judgment
        self.mental = mental
    }

    /// 다섯 능력치가 모두 같은 선수.
    public static func uniform(_ value: Double) -> DuelSkills {
        DuelSkills(control: value, macro: value, strategy: value, judgment: value, mental: value)
    }

    public static var keys: [WritableKeyPath<DuelSkills, Double>] { [\.control, \.macro, \.strategy, \.judgment, \.mental] }

    public static let labels = ["컨트롤", "운영", "전략", "판단", "멘탈"]

    /// 종족의 비중으로 낸 종합 능력.
    public func overall(_ race: DuelRace) -> Double {
        let weights = race.weights
        return Self.keys.reduce(0) { $0 + self[keyPath: $1] * weights[keyPath: $1] }
    }
}

/// 경기 전에 고르는 플레이 스타일.
public enum DuelStyle: String, Codable, CaseIterable, Sendable {
    case balanced, rush, macro, gambit

    public var label: String {
        switch self {
        case .balanced: "균형"
        case .rush: "러시형"
        case .macro: "운영형"
        case .gambit: "전략형"
        }
    }

    /// 빌드를 고르는 비중: 초반 공격, 안정, 빠른 확장.
    var buildWeights: [Double] {
        switch self {
        case .balanced: [1, 1, 1]
        case .rush: [2.4, 1, 0.6]
        case .macro: [0.5, 1, 2.2]
        case .gambit: [1, 1, 1]
        }
    }
}

/// 세트 처음에 고르는 빌드. 가위바위보처럼 물고 물린다: 초반 공격 > 빠른 확장 > 안정 > 초반 공격.
public enum DuelBuild: String, Codable, CaseIterable, Sendable {
    case aggressive, standard, fastExpand

    public var label: String {
        switch self {
        case .aggressive: "초반 공격"
        case .standard: "안정"
        case .fastExpand: "빠른 확장"
        }
    }

    /// 이 빌드가 이기는 빌드.
    public var beats: DuelBuild {
        switch self {
        case .aggressive: .fastExpand
        case .fastExpand: .standard
        case .standard: .aggressive
        }
    }

    /// 이 빌드를 이기는 빌드.
    public var counter: DuelBuild {
        DuelBuild.allCases.first { $0.beats == self }!
    }
}

/// 세트의 무게. 큰 경기일수록 멘탈이 크게 작용한다.
public enum DuelStakes: String, Codable, CaseIterable, Sendable {
    /// 정규 시즌의 보통 세트.
    case regular
    /// 1 : 1, 2 : 2에서 갈리는 에이스 결정전.
    case ace
    /// 결승.
    case final

    var mentalWeight: Double {
        switch self {
        case .regular: 1
        case .ace: 1.6
        case .final: 2.2
        }
    }
}

/// 맵. 크기와 확장 지형에 따라 빌드와 종족의 유불리가 조금씩 달라진다.
public struct DuelMap: Codable, Equatable, Sendable {
    public enum Shape: String, Codable, Sendable {
        /// 본진이 가깝다. 초반 공격이 강하다.
        case narrow
        /// 본진이 멀다. 빠른 확장이 편하다.
        case wide
        /// 확장할 자리가 많다. 장기전이 된다.
        case open
    }

    public var name: String
    public var shape: Shape
    /// 이 맵에서 조금 유리한 종족 (없으면 nil).
    public var favors: DuelRace?

    public init(name: String, shape: Shape, favors: DuelRace?) {
        self.name = name
        self.shape = shape
        self.favors = favors
    }

    /// 초반 공격의 힘 배수.
    var rushPower: Double {
        switch shape {
        case .narrow: 1.12
        case .wide: 0.9
        case .open: 1.0
        }
    }

    /// 지을 수 있는 확장 수 (본진 포함).
    var maxBases: Int {
        switch shape {
        case .narrow: 4
        case .wide: 5
        case .open: 6
        }
    }

    /// 종족에 따른 싸움 힘 배수.
    func bias(_ race: DuelRace) -> Double {
        favors == race ? 1.03 : 1
    }

    /// 한 시즌에 돌려 쓰는 맵 다섯 개.
    public static let pool: [DuelMap] = [
        DuelMap(name: "청동 협곡", shape: .narrow, favors: .alien),
        DuelMap(name: "푸른 고원", shape: .wide, favors: .protector),
        DuelMap(name: "잿빛 평원", shape: .open, favors: .human),
        DuelMap(name: "얼음 분지", shape: .wide, favors: nil),
        DuelMap(name: "황혼 요새", shape: .narrow, favors: .human),
    ]

    /// "휴먼이 조금 유리한 맵입니다" 같은 한 줄 소개.
    public var note: String {
        let shapeText = switch shape {
        case .narrow: "본진이 가까운 좁은 맵"
        case .wide: "본진이 먼 넓은 맵"
        case .open: "확장할 자리가 많은 맵"
        }
        if let favors { return "\(shapeText), \(favors.label)이 조금 유리한 맵입니다" }
        return "\(shapeText)입니다"
    }
}

/// 세트에 나서는 선수 한 명.
public struct DuelPlayer: Codable, Equatable, Sendable {
    public var name: String
    public var race: DuelRace
    public var skills: DuelSkills
    public var style: DuelStyle

    public init(name: String, race: DuelRace, skills: DuelSkills, style: DuelStyle = .balanced) {
        self.name = name
        self.race = race
        self.skills = skills
        self.style = style
    }

    public var overall: Double { skills.overall(race) }
}

extension String {
    /// 받침에 맞춰 주격 조사를 붙인다: "김하늘이", "이수가".
    var withSubject: String {
        guard let last = unicodeScalars.last, (0xAC00...0xD7A3).contains(last.value) else { return self + "이(가)" }
        return self + ((last.value - 0xAC00) % 28 == 0 ? "가" : "이")
    }
}
