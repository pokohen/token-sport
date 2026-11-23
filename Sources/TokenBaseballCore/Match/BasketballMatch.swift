import Foundation

/// 진행 중인 농구 경기 한 판. `step()`을 부를 때마다 경기 시간 8초가 흐른다.
/// 10분 4쿼터이고, 동점이면 승부가 날 때까지 5분씩 연장한다 (무승부가 없다).
/// 난수 상태까지 통째로 저장되므로, 저장했다가 다시 읽어도 똑같이 이어진다.
///
/// 공격 한 번(공격권)은 한 틱에서 세 틱 사이에 끝난다. 끝나는 틱에 실책, 슛, 반칙 가운데 하나가 일어나고,
/// 슛이 빗나가면 리바운드를 다툰다. 공격 리바운드를 잡으면 짧은 공격이 이어진다.
public struct BasketballMatch: Codable, Equatable, Sendable {
    public static let secondsPerStep = 8
    public static let quarterLength = 10 * 60
    public static let overtimeLength = 5 * 60
    public static let quarters = 4
    /// 이 수의 개인 반칙이면 퇴장이다.
    public static let foulLimit = 5
    static let logLimit = 80

    public var rules: BasketballRules
    public var home: BasketballSide
    public var away: BasketballSide
    public var rng: SeededRNG

    /// 지금 쿼터 (1부터). 5 이상이면 연장이다.
    public internal(set) var period = 1
    /// 이번 쿼터에서 흐른 시간(초).
    public internal(set) var clock = 0
    public internal(set) var homeHasBall = false
    public internal(set) var isFinished = false
    /// 최근 문자 중계 (오래된 것부터).
    public internal(set) var log: [MatchEvent] = []

    /// 이번 공격이 끝나기까지 남은 틱.
    var possessionSteps = 1
    /// 공격 리바운드 뒤의 공격인지 (골밑 슛이 많아진다).
    var secondChance = false

    public init(away: BasketballSide, home: BasketballSide, rules: BasketballRules, seed: UInt64) {
        self.rules = rules
        self.away = away
        self.home = home
        self.rng = SeededRNG(seed: seed)
        self.home.pointsByPeriod = [0]
        self.away.pointsByPeriod = [0]
        // 점프볼
        self.homeHasBall = rng.chance(0.5)
        self.possessionSteps = rng.int(1...3)
    }

    // MARK: 읽기

    public var result: MatchResult? {
        guard isFinished else { return nil }
        return home.points > away.points ? .homeWin : .awayWin
    }

    public var isOvertime: Bool { period > Self.quarters }
    public var wentToOvertime: Bool { home.pointsByPeriod.count > Self.quarters }

    var periodLength: Int { isOvertime ? Self.overtimeLength : Self.quarterLength }

    /// "3쿼터", "연장", "2차 연장".
    public var periodLabel: String {
        if isFinished { return "경기 종료" }
        if !isOvertime { return "\(period)쿼터" }
        let extra = period - Self.quarters
        return extra == 1 ? "연장" : "\(extra)차 연장"
    }

    /// "3Q 7:32" 같은 표시 (쿼터와 남은 시간).
    public var clockLabel: String {
        if isFinished { return "종료" }
        let left = max(0, periodLength - clock)
        let tag = isOvertime ? "연장" : "\(period)Q"
        return "\(tag) \(left / 60):\(String(format: "%02d", left % 60))"
    }

    /// 정규 시간 기준으로 지금까지 흐른 시간(초). 연장은 40분 뒤에 이어 센다.
    public var elapsed: Int {
        let before = min(period - 1, Self.quarters) * Self.quarterLength
            + max(0, period - 1 - Self.quarters) * Self.overtimeLength
        return before + min(clock, periodLength)
    }

    public var scoreText: String {
        "\(away.shortName) \(away.points) : \(home.points) \(home.shortName)"
    }

    var attacking: BasketballSide {
        get { homeHasBall ? home : away }
        set { if homeHasBall { home = newValue } else { away = newValue } }
    }

    var defending: BasketballSide {
        get { homeHasBall ? away : home }
        set { if homeHasBall { away = newValue } else { home = newValue } }
    }

    // MARK: 진행

    /// 한 틱을 진행하고, 그동안 일어난 일을 돌려준다.
    @discardableResult
    public mutating func step() -> [MatchEvent] {
        guard !isFinished else { return [] }
        var events: [MatchEvent] = []

        if clock >= periodLength {
            endPeriod(&events)
        } else {
            if clock == 0, period == 1, log.isEmpty {
                say(&events, .inning, "점프볼! \(attacking.shortName)의 공격으로 시작합니다")
            }
            possessionSteps -= 1
            if possessionSteps <= 0 { resolvePossession(&events) }
            // 쿼터의 마지막 틱은 남은 시간만큼만 센다 (연장 5분은 8초로 나누어떨어지지 않는다).
            tire(seconds: min(Self.secondsPerStep, periodLength - clock))
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

    /// 홈 이점: 슛 성공률에 더하는 값. 중립 구장이면 없다.
    var homeBoost: Double { rules.neutral == true ? 0 : rules.homeEdge * 0.55 }

    func boost(forHome isHome: Bool) -> Double { isHome ? homeBoost : 0 }

    // MARK: 쿼터

    mutating func endPeriod(_ events: inout [MatchEvent]) {
        let regulationOver = period >= Self.quarters
        if regulationOver, home.points != away.points {
            isFinished = true
            say(&events, .end, "경기 종료! \(scoreText)")
            return
        }
        if regulationOver {
            say(&events, .inning, "\(periodLabel) 종료, \(scoreText). 승부를 가리지 못해 연장으로 갑니다")
        } else {
            say(&events, .inning, "\(periodLabel) 종료, \(scoreText)")
        }
        // 쉬는 시간: 하프타임에는 더 많이 회복한다.
        let rest = period == 2 ? 0.2 : 0.1
        for isHome in [true, false] {
            var side = isHome ? home : away
            for index in side.players.indices {
                side.players[index].energy = min(1, side.players[index].energy + rest)
            }
            side.pointsByPeriod.append(0)
            if isHome { home = side } else { away = side }
        }
        period += 1
        clock = 0
        secondChance = false
        possessionSteps = rng.int(1...3)
        // 쿼터마다 공격권을 번갈아 준다.
        homeHasBall = period % 2 == 0 ? !homeHasBall : homeHasBall
        substitute(&events)
    }

    // MARK: 체력과 교체

    /// 코트 위에서는 지치고, 벤치에서는 회복한다. 뛴 시간도 여기서 센다.
    mutating func tire(seconds: Int) {
        for isHome in [true, false] {
            var side = isHome ? home : away
            for index in side.players.indices {
                if side.players[index].isOnCourt {
                    var amount = 0.0040 * (1.15 - side.players[index].stamina / 100 * 0.45)
                    if side.players[index].traits.contains(.ironLungs) { amount *= 0.7 }
                    amount *= side.players[index].style?.drain ?? 1
                    side.players[index].energy = max(0.2, side.players[index].energy - amount)
                    side.players[index].line.seconds += seconds
                } else {
                    side.players[index].energy = min(1, side.players[index].energy + 0.006)
                }
            }
            if isHome { home = side } else { away = side }
        }
    }

    /// 공격이 끝날 때마다 벤치를 살핀다: 지친 선수와 반칙이 많은 선수를 쉬게 하고,
    /// 선수 모드의 내 선수가 벤치에 있으면 정해진 시간만큼 뛰게 한다.
    mutating func substitute(_ events: inout [MatchEvent]) {
        for isHome in [true, false] {
            var side = isHome ? home : away
            let progress = Double(min(elapsed, Self.quarters * Self.quarterLength))
                / Double(Self.quarters * Self.quarterLength)

            // 내 선수의 출전 시간 보장.
            if let id = side.featured, let target = side.featuredMinutes,
               let mine = side.players.firstIndex(where: { $0.playerID == id }), !side.players[mine].fouledOut {
                let due = Double(target * 60) * progress
                let played = Double(side.players[mine].line.seconds)
                if !side.players[mine].isOnCourt, played < due - 30 || isOvertime && side.players[mine].isStarter {
                    if let out = Self.weakestOnCourt(side, like: side.players[mine].natural, except: mine) {
                        Self.swap(&side, out: out, in: mine)
                        events.append(MatchEvent(.change, "\(clockLabel) \(side.shortName) 교체: \(side.players[out].name) 나가고 \(side.players[mine].name) 들어옵니다"))
                    }
                } else if side.players[mine].isOnCourt, !side.players[mine].isStarter, !isOvertime,
                          played > due + 150 {
                    if let incoming = Self.bestOnBench(side, like: side.players[mine].slot, except: mine) {
                        Self.swap(&side, out: mine, in: incoming)
                        events.append(MatchEvent(.change, "\(clockLabel) \(side.shortName) 교체: \(side.players[mine].name) 나가고 \(side.players[incoming].name) 들어옵니다"))
                    }
                }
            }

            // 다섯 번째 반칙으로 물러난 선수는 곧바로 나간다 (벤치에 뛸 수 있는 선수가 한 명이라도 있으면).
            for index in side.players.indices where side.players[index].isOnCourt && side.players[index].fouledOut {
                let bench = side.players.indices.filter { !side.players[$0].isOnCourt && !side.players[$0].fouledOut }
                let slot = side.players[index].slot
                guard let incoming = bench.max(by: {
                    (side.players[$0].natural == slot ? 1 : 0, side.players[$0].energy, -$0)
                        < (side.players[$1].natural == slot ? 1 : 0, side.players[$1].energy, -$1)
                }) else { continue }
                Self.swap(&side, out: index, in: incoming)
                events.append(MatchEvent(.change, "\(clockLabel) \(side.shortName) 교체: \(side.players[index].name) 나가고 \(side.players[incoming].name) 들어옵니다"))
            }

            // 지친 선수를 쉬게 한다. 마지막 3분과 연장에는 주전을 다시 올린다.
            let closing = (period == Self.quarters && clock >= Self.quarterLength - 180) || isOvertime
            for index in side.players.indices where side.players[index].isOnCourt {
                let player = side.players[index]
                if player.playerID == side.featured { continue }
                let tired = player.energy < (closing ? 0.3 : 0.55)
                let returning = closing && !player.isStarter
                guard tired || returning else { continue }
                let candidate = closing
                    ? Self.bestOnBench(side, like: player.slot, except: nil, startersFirst: true, minEnergy: 0.35)
                    : Self.bestOnBench(side, like: player.slot, except: nil, minEnergy: 0.8)
                guard let incoming = candidate else { continue }
                // 마무리에는 벤치 선수를 더 나은 주전으로만 바꾼다.
                if returning, !tired, !side.players[incoming].isStarter { continue }
                Self.swap(&side, out: index, in: incoming)
            }
            if isHome { home = side } else { away = side }
        }
    }

    static func swap(_ side: inout BasketballSide, out: Int, in incoming: Int) {
        side.players[incoming].slot = side.players[out].slot
        side.players[out].isOnCourt = false
        side.players[incoming].isOnCourt = true
        if !side.players[incoming].hasPlayed {
            side.players[incoming].hasPlayed = true
            side.players[incoming].line.games = 1
        }
    }

    /// 코트 위에서 내보낼 선수: 같은 자리의 선수 가운데 가장 지친 선수. 없으면 아무 자리에서나.
    static func weakestOnCourt(_ side: BasketballSide, like position: Position, except: Int) -> Int? {
        let court = side.onCourt.filter { $0 != except }
        let same = court.filter { side.players[$0].slot == position }
        return (same.isEmpty ? court : same).min {
            (side.players[$0].energy, $0) < (side.players[$1].energy, $1)
        }
    }

    /// 벤치에서 올릴 선수: 같은 포지션을 먼저, 그다음은 체력이 많이 남은 순서.
    static func bestOnBench(
        _ side: BasketballSide, like position: Position, except: Int?,
        startersFirst: Bool = false, minEnergy: Double = 0
    ) -> Int? {
        let bench = side.players.indices.filter {
            !side.players[$0].isOnCourt && !side.players[$0].fouledOut && $0 != except
                && side.players[$0].energy >= minEnergy && side.players[$0].playerID != side.featured
        }
        func key(_ index: Int) -> (Int, Int, Double) {
            let player = side.players[index]
            return (
                startersFirst && player.isStarter ? 1 : 0,
                player.natural == position ? 1 : 0,
                player.energy)
        }
        return bench.max { key($0) < key($1) }
    }

    // MARK: 공격 한 번

    /// 슛을 나눠 갖는 비중. 능력 30과 90이 1.5배쯤 차이 난다 (정비례면 세 배).
    /// 잘하는 선수의 득점은 슛 수보다 성공률과 뛰는 시간에서 더 벌어진다.
    static func shotShare(_ skill: Double) -> Double {
        pow(max(5, skill), 0.4)
    }

    mutating func resolvePossession(_ events: inout [MatchEvent]) {
        let offense = attacking, defense = defending
        let five = offense.onCourt, guards = defense.onCourt
        guard !five.isEmpty, !guards.isEmpty else {
            changePossession(&events)
            return
        }

        // 1. 실책
        let handle = offense.mean { $0.dribbling * 0.6 + $0.passing * 0.4 }
        let pressure = defense.mean { $0.defense * 0.6 + $0.speed * 0.4 }
        let turnover = clamp(0.2 - handle * 0.0011 + (pressure - handle) * 0.0025, 0.06, 0.26)
        if !secondChance, rng.chance(turnover) {
            let loser = five[rng.weighted(five.map { 140 - offense.players[$0].dribbling })]
            attacking.players[loser].line.turnovers += 1
            if rng.chance(0.55) {
                let thief = guards[rng.weighted(guards.map {
                    let player = defense.players[$0]
                    return (player.defense + player.speed) * (player.style?.defenseWeight ?? 1)
                })]
                defending.players[thief].line.steals += 1
                say(&events, .play, "\(defense.shortName) \(defense.players[thief].name) \(rng.pick(Self.stealLines))")
            } else {
                say(&events, .play, "\(offense.shortName) \(offense.players[loser].name) \(rng.pick(Self.turnoverLines))")
            }
            changePossession(&events)
            return
        }

        // 2. 누가 던지는가
        let shooter = five[rng.weighted(five.map { index in
            let player = offense.players[index]
            let role: Double
            switch player.slot {
            case .shootingGuard: role = 1.25
            case .smallForward: role = 1.15
            case .pointGuard: role = 0.95
            case .powerForward: role = 0.9
            default: role = 0.8
            }
            // 잘 던지는 선수에게 공이 더 가지만, 능력에 정비례하지는 않는다 (한 명이 슛을 독차지하지 않게).
            return Self.shotShare(player.shooting * 0.6 + player.three * 0.4) * role * (player.style?.shotWeight ?? 1)
        })]
        let me = offense.players[shooter]
        // 맞은편 수비수: 같은 자리의 선수. 없으면 아무나.
        let marker = guards.first { defense.players[$0].slot == me.slot } ?? rng.pick(guards)
        let stopper = defense.players[marker]
        let teamDefense = defense.mean { $0.defense }
        let resistance = stopper.defense * stopper.fatigue * 0.6 + teamDefense * 0.4

        // 3. 어디서 던지는가
        let outside: Double
        switch me.slot {
        case .shootingGuard: outside = 0.16
        case .pointGuard: outside = 0.1
        case .smallForward: outside = 0.04
        case .powerForward: outside = -0.08
        default: outside = -0.16
        }
        let greedy = me.style == .greedy
        let isThree = !secondChance && rng.chance(clamp(0.24 + outside + (me.three - me.shooting) * 0.005, 0.03, 0.6))

        // 4. 슛 반칙
        if rng.chance(isThree ? 0.03 : 0.13) {
            foul(by: marker, on: shooter, shots: isThree ? 3 : 2, &events)
            return
        }

        // 5. 들어가는가
        let edge = boost(forHome: homeHasBall) - boost(forHome: !homeHasBall)
        let skill = (isThree ? me.three : me.shooting * 0.8 + me.physical * 0.2) * me.fatigue
        var make = isThree
            ? 0.215 + skill * 0.002 + (skill - resistance) * 0.0035
            : 0.36 + skill * 0.0026 + (skill - resistance) * 0.004
        make += edge + (secondChance ? 0.06 : 0) - (greedy ? 0.03 : 0)
        if me.traits.contains(.clutch), period >= Self.quarters, abs(home.points - away.points) <= 5 { make += 0.04 }
        make = clamp(make, isThree ? 0.12 : 0.22, isThree ? 0.55 : 0.72)

        attacking.players[shooter].line.fieldGoalsAttempted += 1
        if isThree { attacking.players[shooter].line.threesAttempted += 1 }

        if rng.chance(make) {
            let value = isThree ? 3 : 2
            score(shooter, value)
            attacking.players[shooter].line.fieldGoalsMade += 1
            if isThree { attacking.players[shooter].line.threesMade += 1 }
            // 도움
            var helper: Int?
            let mates = five.filter { $0 != shooter }
            if !mates.isEmpty, rng.chance(isThree ? 0.72 : 0.52) {
                let index = mates[rng.weighted(mates.map {
                    let player = offense.players[$0]
                    return max(5, player.passing) * (player.slot == .pointGuard ? 1.8 : 1)
                        * (player.style?.assistWeight ?? 1)
                })]
                attacking.players[index].line.assists += 1
                helper = index
            }
            let lines = isThree ? Self.threeLines : secondChance ? Self.putBackLines : Self.twoLines
            let assist = helper.map { " (\(offense.players[$0].name) 도움)" } ?? ""
            say(&events, .score, "\(offense.shortName) \(me.name) \(rng.pick(lines))\(assist) · \(scoreText)")
            changePossession(&events)
            return
        }

        // 6. 빗나갔다: 블록, 그리고 리바운드
        if !isThree, rng.chance(clamp(0.1 + (stopper.defense - me.shooting) * 0.0015, 0.04, 0.2)) {
            let bigs = guards.filter { [.powerForward, .center5].contains(defense.players[$0].slot) }
            let blocker = (bigs.isEmpty ? guards : bigs)[rng.weighted((bigs.isEmpty ? guards : bigs).map {
                let player = defense.players[$0]
                return (player.defense + player.physical) * (player.style?.defenseWeight ?? 1)
            })]
            defending.players[blocker].line.blocks += 1
            say(&events, .play, "\(defense.shortName) \(defense.players[blocker].name) \(rng.pick(Self.blockLines))")
        } else {
            say(&events, .play, "\(offense.shortName) \(me.name) \(rng.pick(isThree ? Self.threeMissLines : Self.missLines))")
        }
        rebound(&events)
    }

    /// 리바운드 다툼. 공격 쪽이 잡으면 공격이 이어진다.
    mutating func rebound(_ events: inout [MatchEvent]) {
        let offense = attacking, defense = defending
        func weight(_ player: BasketballPlayerState) -> Double {
            let role: Double
            switch player.slot {
            case .center5: role = 2.6
            case .powerForward: role = 2.2
            case .smallForward: role = 1.2
            default: role = 0.7
            }
            return max(5, player.rebounding * 0.7 + player.physical * 0.3) * role * player.fatigue
                * (player.style?.defenseWeight ?? 1).squareRoot()
        }
        let attack = offense.onCourt.reduce(0) { $0 + weight(offense.players[$1]) }
        let defend = defense.onCourt.reduce(0) { $0 + weight(defense.players[$1]) }
        let offensive = clamp(0.27 * (attack / max(1, defend)), 0.14, 0.42)
        if rng.chance(offensive) {
            let five = offense.onCourt
            let index = five[rng.weighted(five.map { weight(offense.players[$0]) })]
            attacking.players[index].line.rebounds += 1
            say(&events, .play, "\(offense.shortName) \(offense.players[index].name), 공격 리바운드를 잡아냅니다")
            secondChance = true
            possessionSteps = 1
        } else {
            let five = defense.onCourt
            let index = five[rng.weighted(five.map { weight(defense.players[$0]) })]
            defending.players[index].line.rebounds += 1
            changePossession(&events)
        }
    }

    /// 슛 동작 반칙: 자유투를 던진다. 다섯 번째 반칙이면 퇴장이다.
    mutating func foul(by marker: Int, on shooter: Int, shots: Int, _ events: inout [MatchEvent]) {
        defending.players[marker].line.fouls += 1
        let fouler = defending.players[marker]
        let me = attacking.players[shooter]
        let rate = clamp(0.5 + me.shooting * 0.004 + boost(forHome: homeHasBall), 0.45, 0.92)
        var made = 0
        for _ in 0..<shots where rng.chance(rate) { made += 1 }
        attacking.players[shooter].line.freeThrowsAttempted += shots
        attacking.players[shooter].line.freeThrowsMade += made
        if made > 0 { score(shooter, made) }
        say(&events, made > 0 ? .score : .play,
            "\(defending.shortName) \(fouler.name)의 반칙. \(attacking.shortName) \(me.name), 자유투 \(shots)개 중 \(made)개 성공 · \(scoreText)")
        if fouler.line.fouls >= Self.foulLimit {
            defending.players[marker].fouledOut = true
            say(&events, .change, "\(defending.shortName) \(fouler.name), 다섯 번째 반칙으로 물러납니다")
        }
        // 마지막 자유투가 빗나가면 리바운드, 들어가면 공격권이 넘어간다.
        if made < shots, rng.chance(0.5) { rebound(&events) } else { changePossession(&events) }
    }

    mutating func score(_ shooter: Int, _ value: Int) {
        attacking.players[shooter].line.points += value
        attacking.points += value
        attacking.pointsByPeriod[attacking.pointsByPeriod.count - 1] += value
    }

    mutating func changePossession(_ events: inout [MatchEvent]) {
        homeHasBall.toggle()
        secondChance = false
        possessionSteps = rng.weighted([0.32, 0.5, 0.18]) + 1
        substitute(&events)
    }

    // MARK: 중계 문구

    static let twoLines = [
        "골밑 돌파 성공!", "미들슛이 림을 가릅니다!", "레이업으로 마무리합니다!", "페이드어웨이 슛, 들어갑니다!",
        "컷인 후 깔끔한 마무리!", "포스트업에서 훅슛, 득점!",
    ]
    static let putBackLines = ["리바운드에 이은 풋백 득점!", "다시 올려놓습니다, 득점!", "세컨드 찬스를 살립니다!"]
    static let threeLines = [
        "3점슛, 깨끗하게 들어갑니다!", "외곽에서 3점포 작렬!", "코너에서 3점슛 성공!", "스텝백 3점, 꽂힙니다!",
    ]
    static let missLines = ["슛이 림을 맞고 나옵니다", "골밑 슛이 빗나갑니다", "미들슛이 짧습니다"]
    static let threeMissLines = ["3점슛이 림을 돌아 나옵니다", "외곽슛이 빗나갑니다"]
    static let blockLines = ["슛을 쳐냅니다, 블록!", "골밑에서 완벽한 블록!"]
    static let stealLines = ["패스 길을 읽고 가로챕니다!", "공을 낚아챕니다, 스틸!"]
    static let turnoverLines = ["패스가 끊깁니다", "트래블링, 공격권을 넘겨줍니다", "공을 놓칩니다", "24초 바이얼레이션"]
}
