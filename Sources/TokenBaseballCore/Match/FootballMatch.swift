import Foundation

/// 진행 중인 축구 경기 한 판. `step()`을 부를 때마다 경기 시간 20초(승부차기는 한 번의 킥)가 흐른다.
/// 난수 상태까지 통째로 저장되므로, 저장했다가 다시 읽어도 똑같이 이어진다.
public struct FootballMatch: Codable, Equatable, Sendable {
    public enum Period: String, Codable, Sendable {
        case firstHalf, secondHalf, extraFirst, extraSecond, shootout, finished

        var length: Int {
            switch self {
            case .firstHalf, .secondHalf: 45 * 60
            case .extraFirst, .extraSecond: 15 * 60
            default: 0
            }
        }

        var startMinute: Int {
            switch self {
            case .firstHalf: 0
            case .secondHalf: 45
            case .extraFirst: 90
            case .extraSecond: 105
            default: 120
            }
        }
    }

    enum SetPiece: String, Codable, Sendable { case corner, freeKick, penalty }

    public static let secondsPerStep = 20
    static let logLimit = 80

    public var rules: FootballRules
    public var home: FootballSide
    public var away: FootballSide
    public var rng: SeededRNG

    public internal(set) var period = Period.firstHalf
    /// 이번 전·후반에서 흐른 시간(초).
    public internal(set) var clock = 0
    /// 이번 전·후반의 추가시간(초).
    public internal(set) var added = 0
    public internal(set) var homeHasBall = false
    /// 공이 있는 구역. 공을 가진 팀 기준으로 0 = 자기 진영, 1 = 중원, 2 = 상대 진영.
    public internal(set) var zone = 1
    public internal(set) var isFinished = false
    /// 최근 문자 중계 (오래된 것부터).
    public internal(set) var log: [MatchEvent] = []

    var pending: SetPiece?
    var announcedAdded = false
    var homeKicksNext = false

    public init(away: FootballSide, home: FootballSide, rules: FootballRules, seed: UInt64) {
        self.rules = rules
        self.away = away
        self.home = home
        self.rng = SeededRNG(seed: seed)
        self.added = rng.int(1...4) * 60
    }

    // MARK: 읽기

    public var result: MatchResult? {
        guard isFinished else { return nil }
        // 승부차기까지 갔으면 승부차기로 정한다. 두 경기 합산의 2차전은 그날 점수가 달라도
        // 합산이 같아 승부차기로 갈 수 있으므로, 점수보다 먼저 본다.
        if wentToShootout, home.shootoutGoals != away.shootoutGoals {
            return home.shootoutGoals > away.shootoutGoals ? .homeWin : .awayWin
        }
        if home.goals != away.goals { return home.goals > away.goals ? .homeWin : .awayWin }
        return .draw
    }

    public var wentToShootout: Bool { home.shootoutKicks > 0 }

    /// "67'", "45+2'", "승부차기" 같은 경기 시간 표시.
    public var clockLabel: String {
        switch period {
        case .shootout: return "승부차기"
        case .finished: return "종료"
        default:
            let length = period.length
            if clock >= length {
                return "\(period.startMinute + length / 60)+\((clock - length) / 60 + 1)'"
            }
            return "\(period.startMinute + clock / 60 + 1)'"
        }
    }

    public var periodLabel: String {
        switch period {
        case .firstHalf: "전반"
        case .secondHalf: "후반"
        case .extraFirst: "연장 전반"
        case .extraSecond: "연장 후반"
        case .shootout: "승부차기"
        case .finished: "경기 종료"
        }
    }

    /// 지금까지 흐른 경기 시간(분).
    public var minute: Int { period.startMinute + min(clock, period.length) / 60 }

    /// 홈 팀 점유율 (0~1).
    public var homePossession: Double {
        let total = home.possession + away.possession
        return total == 0 ? 0.5 : Double(home.possession) / Double(total)
    }

    /// 홈 팀 기준으로 공이 있는 구역 (0 = 홈 진영, 2 = 원정 진영).
    public var ballZoneFromHome: Int { homeHasBall ? zone : 2 - zone }

    public var scoreText: String {
        var text = "\(away.shortName) \(away.goals) : \(home.goals) \(home.shortName)"
        if wentToShootout { text += " (승부차기 \(away.shootoutGoals):\(home.shootoutGoals))" }
        return text
    }

    var attacking: FootballSide {
        get { homeHasBall ? home : away }
        set { if homeHasBall { home = newValue } else { away = newValue } }
    }

    var defending: FootballSide {
        get { homeHasBall ? away : home }
        set { if homeHasBall { away = newValue } else { home = newValue } }
    }

    // MARK: 진행

    /// 한 틱을 진행하고, 그동안 일어난 일을 돌려준다.
    @discardableResult
    public mutating func step() -> [MatchEvent] {
        guard !isFinished else { return [] }
        var events: [MatchEvent] = []

        if period == .shootout {
            takeShootoutKick(&events)
        } else if clock >= period.length + added, pending != .penalty {
            endPeriod(&events)
        } else {
            if clock >= period.length, !announcedAdded {
                announcedAdded = true
                say(&events, .inning, "추가시간 \(added / 60)분")
            }
            substitute(&events)
            if let piece = pending {
                pending = nil
                resolve(piece, &events)
            } else {
                play(&events)
            }
            tire()
            attacking.possession += 1
            clock += Self.secondsPerStep
        }

        log.append(contentsOf: events)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        return events
    }

    /// 화면 없이 끝까지 돌린다 (다른 구장 경기와 테스트용).
    public mutating func runToEnd() {
        while !isFinished { step() }
    }

    func say(_ events: inout [MatchEvent], _ kind: MatchEvent.Kind, _ text: String) {
        events.append(MatchEvent(kind, "\(clockLabel) \(text)"))
    }

    // MARK: 능력 비교

    /// 홈 이점. 중립 구장이면 없다.
    var edgePoints: Double { rules.neutral == true ? 0 : 1.3 + rules.homeEdge * 110 }

    func bonus(home isHome: Bool) -> Double { isHome ? edgePoints : 0 }

    /// 공격 쪽이 수비 쪽보다 나은 정도를 확률 배율로 바꾼다.
    func ratio(_ attack: Double, _ defense: Double) -> Double {
        let a = attack + attacking.tactic.attackShift - attacking.shortHanded + bonus(home: homeHasBall)
        let d = defense - defending.tactic.attackShift - defending.shortHanded + bonus(home: !homeHasBall)
        return clamp(exp((a - d) / 90), 0.4, 2.5)
    }

    mutating func flip(to newZone: Int) {
        homeHasBall.toggle()
        zone = newZone
    }

    // MARK: 한 틱

    mutating func play(_ events: inout [MatchEvent]) {
        let roll = rng.unit()
        switch zone {
        case 0:
            let m = ratio(
                attacking.mean([.defender, .midfielder]) { $0.passing },
                defending.mean([.forward, .midfielder]) { $0.tackling * 0.5 + $0.speed * 0.5 })
            let advance = clamp(0.58 * m, 0.25, 0.85)
            let lose = clamp(0.08 / m, 0.02, 0.25)
            if roll < advance {
                zone = 1
                say(&events, .play, "\(attacking.shortName) \(holder([.defender, .midfielder], credit: \.advances)) \(rng.pick(Self.buildUpLines))")
            } else if roll < advance + lose {
                let thief = name(of: defending, in: [.forward, .midfielder], credit: \.tackles)
                flip(to: 2)
                say(&events, .play, "\(attacking.shortName) \(thief), 높은 위치에서 공을 뺏습니다!")
            } else {
                say(&events, .play, "\(attacking.shortName), 뒤에서 공을 돌립니다")
            }
        case 1:
            let m = ratio(
                attacking.mean([.midfielder]) { $0.passing * 0.6 + $0.dribbling * 0.4 }
                    + attacking.shape.midfieldShift,
                defending.mean([.midfielder]) { $0.tackling * 0.7 + $0.physical * 0.3 }
                    + defending.shape.midfieldShift)
            let advance = clamp(0.34 * m, 0.12, 0.7)
            let lose = clamp(0.27 / m, 0.08, 0.5)
            if roll < advance {
                zone = 2
                say(&events, .play, "\(attacking.shortName) \(holder([.midfielder, .forward], credit: \.advances)) \(rng.pick(Self.advanceLines))")
            } else if roll < advance + lose {
                if rng.chance(0.42) {
                    foul(dangerous: false, &events)
                } else {
                    let thief = name(of: defending, in: [.midfielder, .defender], credit: \.tackles)
                    flip(to: 1)
                    say(&events, .play, "\(attacking.shortName) \(thief) \(rng.pick(Self.interceptLines))")
                }
            } else {
                say(&events, .play, "\(attacking.shortName), 중원에서 기회를 엿봅니다")
            }
        default:
            let m = ratio(
                attacking.mean([.forward, .midfielder], weights: [.forward: 2]) {
                    $0.dribbling * 0.4 + $0.speed * 0.3 + $0.passing * 0.3
                } + attacking.shape.attackShift,
                defending.mean([.defender]) { $0.tackling * 0.6 + $0.physical * 0.2 + $0.speed * 0.2 }
                    + defending.shape.defenseShift)
            let shot = clamp(0.21 * m, 0.07, 0.5)
            let penalty = clamp(0.003 * m, 0.001, 0.008)
            let offside = 0.035
            let lose = clamp(0.33 / m, 0.12, 0.6)
            if roll < shot {
                shoot(&events)
            } else if roll < shot + penalty {
                foul(dangerous: true, penalty: true, &events)
            } else if roll < shot + penalty + offside {
                let runner = holder([.forward])
                attacking.offsides += 1
                say(&events, .play, "\(attacking.shortName) \(runner), 오프사이드")
                flip(to: 0)
            } else if roll < shot + penalty + offside + lose {
                let kind = rng.unit()
                if kind < 0.22 {
                    foul(dangerous: true, &events)
                } else if kind < 0.44 {
                    say(&events, .play, "\(defending.shortName) \(name(of: defending, in: [.defender], credit: \.clearances)), 크로스를 걷어내 코너킥")
                    awardCorner()
                } else {
                    let thief = name(of: defending, in: [.defender], credit: \.tackles)
                    let counter = rng.chance(0.2)
                    flip(to: counter ? 1 : 0)
                    say(&events, .play, "\(attacking.shortName) \(thief) \(counter ? "끊어내고 역습!" : rng.pick(Self.clearLines))")
                }
            } else {
                say(&events, .play, "\(attacking.shortName) \(holder([.forward, .midfielder])) \(rng.pick(Self.probeLines))")
            }
        }
    }

    /// 공을 가진 팀에서 이 자리의 선수 이름을 하나 고른다.
    mutating func holder(_ slots: [Position], credit: WritableKeyPath<FootballDetail, Int>? = nil) -> String {
        name(of: attacking, in: slots, credit: credit)
    }

    /// `credit`을 주면 고른 선수의 세부 기록에 한 번을 더한다 (세부 기록을 남기는 선수일 때만).
    mutating func name(
        of side: FootballSide, in slots: [Position], credit: WritableKeyPath<FootballDetail, Int>? = nil
    ) -> String {
        let onPitch = side.players.indices.filter { side.players[$0].isOnPitch }
        let fitting = onPitch.filter { slots.contains(side.players[$0].slot) }
        let pool = fitting.isEmpty ? onPitch : fitting
        guard !pool.isEmpty else { return side.shortName }
        let index: Int
        if let credit, pool.contains(where: { side.players[$0].detail != nil }) {
            // 선수 모드: 내 선수가 있는 팀은 능력치가 좋은 선수가 더 자주 그 일을 한다.
            // (그래야 수비·패스를 훈련한 만큼 평점에 돌아온다.)
            let defensive = credit == \.tackles || credit == \.clearances
            index = pool[rng.weighted(pool.map { slot in
                let player = side.players[slot]
                let skill = defensive ? player.tackling : (player.passing + player.dribbling) / 2
                return Self.skillShare(skill) * (defensive ? player.style?.defenseWeight ?? 1 : 1)
            })]
        } else {
            index = rng.pick(pool)
        }
        if let credit {
            if side.teamID == home.teamID {
                home.players[index].detail?[keyPath: credit] += 1
            } else {
                away.players[index].detail?[keyPath: credit] += 1
            }
        }
        return side.players[index].name
    }

    /// 가중치로 공격 팀 선수 한 명을 고른다.
    mutating func pickAttacker(
        excluding: Int? = nil, _ weight: (FootballPlayerState) -> Double
    ) -> Int? {
        let side = attacking
        var indices: [Int] = []
        var weights: [Double] = []
        for (index, player) in side.players.enumerated()
        where player.isOnPitch && player.slot != .goalkeeper && index != excluding {
            indices.append(index)
            weights.append(max(0.01, weight(player)))
        }
        guard !indices.isEmpty else { return nil }
        return indices[rng.weighted(weights)]
    }

    /// 능력치가 높을수록 그 일을 맡는 몫. 능력 차이가 클수록 몫이 더 가파르게 벌어진다.
    ///
    /// 예전에는 `0.5 + 능력/100`이라 슈팅 90과 25의 몫이 1.9배밖에 차이 나지 않았다. 그래서 리그 수준을
    /// 훌쩍 넘는 선수도 슛을 조금 더 가져갈 뿐이었다. 지금은 3.8배다 (90 → 1.97, 60 → 1.22, 25 → 0.52).
    /// 비슷한 선수끼리는 몫이 거의 같아서 팀 전체의 슈팅 수는 달라지지 않는다.
    static func skillShare(_ skill: Double) -> Double {
        pow((max(1, skill) + 20) / 70, 1.5)
    }

    static func slotWeight(_ slot: Position, forward: Double, midfielder: Double, defender: Double) -> Double {
        switch slot {
        case .forward: forward
        case .midfielder: midfielder
        default: defender
        }
    }

    var isTightForAttacker: Bool {
        let diff = attacking.goals - defending.goals
        return diff == 0 || diff == -1
    }

    func shootingValue(_ player: FootballPlayerState) -> Double {
        var value = player.shooting * player.fatigue
        if player.traits.contains(.clutch), isTightForAttacker { value += 6 }
        return value + bonus(home: homeHasBall)
    }

    /// 유효 슈팅이 골이 되는 확률이 슈팅과 골키핑의 차이에 얼마나 민감한지 (작을수록 민감).
    static let keeperSpread = 60.0

    func keepingValue(penalty: Bool = false) -> Double {
        let side = defending
        guard let index = side.keeperIndex else { return 8 }
        let keeper = side.players[index]
        var value = keeper.keeping * keeper.fatigue
        if penalty, keeper.traits.contains(.coolHead) { value += 8 }
        return value + bonus(home: !homeHasBall)
    }
}
