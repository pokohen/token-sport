import Foundation

/// 1:1 대전 세트에서 한 선수의 형편.
public struct DuelSide: Codable, Equatable, Sendable {
    public var player: DuelPlayer
    public internal(set) var build: DuelBuild = .standard
    public internal(set) var workers: Double = 6
    public internal(set) var bases = 1
    public internal(set) var army: Double = 2
    /// 다음 확장을 위해 모아 둔 자원.
    var expansion: Double = 0
    /// 지금까지 가장 많았던 확장 수 (무너진 자리를 다시 짓는지 알려고).
    var mostBases = 1
    /// 초반 공격을 나가는 틱 (초반 공격 빌드가 아니면 0).
    var attackTick = 0
    /// 깜짝 빌드의 결과. 성공하면 +, 읽히면 −. 초반 수입에 곱해진다.
    var gambitEdge: Double = 0

    public internal(set) var armyKilled: Double = 0
    public internal(set) var armyLost: Double = 0
    public internal(set) var workersKilled: Double = 0
    public internal(set) var workersLost: Double = 0
    public internal(set) var fightsWon = 0
    /// 세트 중 가장 크게 밀렸던 정도 (0이면 한 번도 밀리지 않았다, 0.5면 상대의 절반).
    public internal(set) var worstDeficit: Double = 0
    /// 상대의 빌드를 미리 읽었는지.
    public internal(set) var readOpponent = false
    /// 그날의 손 상태. 세트마다 정해지고 싸움 힘과 운영에 곱해진다 (이변의 원천).
    public internal(set) var form: Double = 1

    init(player: DuelPlayer) {
        self.player = player
    }

    /// 형세를 견주는 값: 병력 + 일꾼 + 늘린 확장.
    public var value: Double { army + workers * 1.5 + Double(bases - 1) * 15 }

    var skills: DuelSkills { player.skills }
}

/// 1:1 대전의 세트 하나. `step()`을 부를 때마다 게임 시간 15초가 흐른다.
/// 빌드 → 초반 → 정찰과 견제 → 확장과 교전 → 결전으로 흐르고, 진 쪽이 항복("GG")하면 끝난다.
/// 1배속(3초에 한 틱)으로 3~5분이 걸리도록 맞췄다. 난수 상태까지 저장되므로 저장했다가 이어도 같다.
public struct DuelSet: Codable, Equatable, Sendable {
    public static let gameSecondsPerStep = 15
    /// 이만큼 지나도 끝나지 않으면 형세가 나은 쪽이 이긴다.
    public static let maxSteps = 150
    static let logLimit = 60

    public enum Ending: String, Codable, Sendable {
        /// 초반 공격으로 끝났다.
        case rush
        /// 결전에서 병력이 녹아 항복했다.
        case battle
        /// 시간이 다 되어 형세로 갈렸다.
        case timeout
    }

    public let map: DuelMap
    public let stakes: DuelStakes
    /// 두 선수. 0번과 1번은 대칭이다 (홈 이점이 없다).
    public internal(set) var sides: [DuelSide]
    public var rng: SeededRNG

    public internal(set) var tick = 0
    public internal(set) var isFinished = false
    /// 이긴 선수 (0 또는 1).
    public internal(set) var winner: Int?
    public internal(set) var ending: Ending?
    public internal(set) var finalBattles = 0
    public internal(set) var log: [MatchEvent] = []

    var nextHarass = 14
    var nextSkirmish = 24
    var finalTick = 70
    /// 한쪽이 크게 앞섰을 때 결전을 앞당길 수 있는 가장 이른 틱. 세트마다 다르게 정해 끝나는 시각이 한곳에 몰리지 않게 한다.
    var earliestFinal = 40

    public init(first: DuelPlayer, second: DuelPlayer, map: DuelMap, stakes: DuelStakes = .regular, seed: UInt64) {
        self.map = map
        self.stakes = stakes
        self.sides = [DuelSide(player: first), DuelSide(player: second)]
        self.rng = SeededRNG(seed: seed)
        self.nextHarass = rng.int(13...17)
        self.nextSkirmish = rng.int(16...22)
        self.finalTick = rng.int(62...85)
        self.earliestFinal = rng.int(30...55)
        for index in 0..<2 { sides[index].form = 1 + clamp(rng.gaussian(), -2.5, 2.5) * 0.07 }
    }

    // MARK: 읽기

    /// 게임 시간 "12:30".
    public var clockLabel: String {
        let seconds = tick * Self.gameSecondsPerStep
        return "\(seconds / 60):\(String(format: "%02d", seconds % 60))"
    }

    /// 크게 밀렸다가 이겼는지 (한때 형세가 상대의 70% 아래였다).
    public var isComeback: Bool {
        guard let winner else { return false }
        return sides[winner].worstDeficit >= 0.3
    }

    /// "확장 3 : 2 · 병력 120 : 85".
    public var scoreboard: String {
        "확장 \(sides[0].bases) : \(sides[1].bases) · 병력 \(Int(sides[0].army.rounded())) : \(Int(sides[1].army.rounded()))"
    }

    // MARK: 진행

    @discardableResult
    public mutating func step() -> [MatchEvent] {
        guard !isFinished else { return [] }
        var events: [MatchEvent] = []
        tick += 1
        if tick == 1 {
            chooseBuilds(&events)
        } else {
            for index in 0..<2 { grow(index, &events) }
            for index in 0..<2 where sides[index].attackTick == tick && !isFinished {
                earlyAttack(by: index, &events)
            }
            if tick == 16, !isFinished { scoutReport(&events) }
            if tick >= nextHarass, tick < 46, !isFinished {
                harass(&events)
                nextHarass = tick + rng.int(5...8)
            }
            var fought = false
            if tick >= nextSkirmish, !isFinished, tick < finalTick {
                fought = skirmish(&events)
                nextSkirmish = tick + rng.int(7...11)
            }
            if !isFinished, !fought, tick >= finalTick || isLopsided {
                finalBattle(&events)
            }
            if !isFinished, tick >= Self.maxSteps { timeout(&events) }
        }
        trackDeficit()
        log.append(contentsOf: events)
        if log.count > Self.logLimit { log.removeFirst(log.count - Self.logLimit) }
        return events
    }

    public mutating func runToEnd() {
        while !isFinished { step() }
    }

    // MARK: 빌드

    mutating func chooseBuilds(_ events: inout [MatchEvent]) {
        say(&events, .inning, "\(map.name). \(map.note)")
        var picks = sides.map { DuelBuild.allCases[rng.weighted($0.player.style.buildWeights)] }
        // 전략이 좋으면 상대가 고를 빌드를 내다보고 그것을 이기는 빌드로 바꾼다. 두 선수가 같은 정보로 동시에 정한다.
        let first = picks
        for index in 0..<2 where rng.chance(sides[index].skills.strategy / 320) {
            picks[index] = first[1 - index].counter
            sides[index].readOpponent = true
        }
        for index in 0..<2 {
            sides[index].build = picks[index]
            switch picks[index] {
            case .aggressive:
                sides[index].army = 6
                sides[index].workers = 6
                sides[index].attackTick = rng.int(8...11)
            case .standard:
                sides[index].army = 3
                sides[index].expansion = 8
            case .fastExpand:
                sides[index].army = 1.5
                sides[index].expansion = 16
            }
        }
        for index in 0..<2 {
            let side = sides[index]
            say(&events, .play, "\(side.player.name)(\(side.player.race.label)) \(buildLine(side.build))")
        }
        // 전략형은 깜짝 빌드를 섞는다. 상대가 정찰로 알아채면 오히려 손해다.
        for index in 0..<2 where sides[index].player.style == .gambit {
            let other = sides[1 - index].skills
            let spotted = rng.chance(0.25 + other.judgment / 250 - (sides[index].skills.strategy - 50) / 400)
            sides[index].gambitEdge = spotted ? -0.2 : 0.12 + sides[index].skills.strategy / 600
            let name = sides[index].player.name
            say(&events, .play, spotted
                ? "\(name), 깜짝 빌드를 준비했지만 상대가 정찰로 알아챕니다"
                : "\(name)의 깜짝 빌드! 상대는 아직 눈치채지 못했습니다")
        }
    }

    func buildLine(_ build: DuelBuild) -> String {
        switch build {
        case .aggressive: "초반 공격 빌드! 일꾼까지 줄이고 병력을 모읍니다"
        case .standard: "안정적인 빌드로 방어 시설부터 올립니다"
        case .fastExpand: "앞마당부터 가져가는 빠른 확장"
        }
    }

    // MARK: 경제

    mutating func grow(_ index: Int, _ events: inout [MatchEvent]) {
        var side = sides[index]
        let macro = 0.8 + side.skills.macro / 250
        let cap = Double(side.bases * 14)
        let holding = side.build == .aggressive && tick <= side.attackTick
        // 다음 확장으로 옮길 일꾼을 몇 기 더 뽑아 둔다 (캐는 것은 기지 한도까지).
        if side.workers < cap + 4 {
            side.workers += min(cap + 4 - side.workers, (holding ? 0.75 : 1.0) * macro)
        }
        var mined = min(side.workers, cap) * 0.12 * macro * side.form
        if tick < 30 { mined *= 1 + side.gambitEdge }
        // 일꾼이 꽉 차면 확장에 더 쓴다.
        // 일꾼이 거의 찼거나 상대보다 확장이 적으면 확장에 더 쓴다.
        let saturated = side.workers >= cap * 0.85 && tick > side.attackTick
        let behind = side.bases < sides[1 - index].bases && tick > side.attackTick
        let share = side.bases >= map.maxBases
            ? 0.85 : max(0.1, armyShare(side) - (saturated ? 0.3 : 0) - (behind ? 0.15 : 0))
        side.army = min(200, side.army + mined * share * side.player.race.armyRate)
        side.expansion += mined * (1 - share)
        let cost = 15 + Double(side.bases) * 10
        if side.expansion >= cost, side.bases < map.maxBases {
            side.bases += 1
            side.expansion -= cost
            if side.bases <= 3 {
                let again = side.bases <= side.mostBases ? "다시 " : ""
                say(&events, .play, "\(side.player.name), \(again)\(side.bases == 2 ? "앞마당" : "세 번째 확장")을 가져갑니다")
            }
            side.mostBases = max(side.mostBases, side.bases)
        }
        sides[index] = side
    }

    func armyShare(_ side: DuelSide) -> Double {
        if tick < 14 {
            switch side.build {
            case .aggressive: return 0.9
            case .standard: return 0.55
            case .fastExpand: return 0.4
            }
        }
        switch side.player.style {
        case .rush: return 0.64
        case .macro: return tick < 40 ? 0.5 : 0.64
        case .balanced, .gambit: return 0.58
        }
    }

    // MARK: 싸움

    /// 지금 싸우면 낼 힘.
    func power(_ index: Int, final: Bool = false) -> Double {
        let side = sides[index]
        let skills = side.skills
        // 컨트롤이 싸움 힘을 가장 크게 바꾸고, 전략(병력 조합)과 판단(싸울 자리)이 조금 보탠다.
        var power = rawStrength(index) * map.bias(side.player.race) * side.form
            * (0.7 + skills.control / 165) * (1 + (skills.strategy - 50) / 250 + (skills.judgment - 50) / 250)
        // 밀리는 쪽은 자기 진영 가까이에서 싸운다.
        if rawStrength(index) < rawStrength(1 - index) { power *= 1.1 }
        let behind = side.value < sides[1 - index].value * 0.85
        if behind || final {
            let weight = stakes.mentalWeight * (behind && final ? 1.5 : 1)
            power *= 1 + (skills.mental - 50) / 200 * weight
        }
        return max(power, 0.01)
    }

    /// 병력의 양과 종족의 싸움 힘만 본 크기 (능력치는 빼고).
    func rawStrength(_ index: Int) -> Double {
        sides[index].army * sides[index].player.race.fightStrength(tick: tick)
    }

    /// 0번 선수가 가져가는 몫 (0~1). 0.5면 팽팽하다.
    mutating func fightShare(_ power0: Double, _ power1: Double, noise: Double) -> Double {
        var spread = noise
        for side in sides where side.player.style == .gambit { spread += 0.12 }
        let edge = Foundation.log(power0 / power1) * 1.3 + rng.gaussian() * spread
        return 1 / (1 + exp(-edge))
    }

    /// 두 쪽이 병력을 잃는다. 몫이 작은 쪽이 더 많이 잃는다.
    mutating func trade(share: Double, scale: Double) {
        let lost0 = sides[0].army * scale * (1 - share)
        let lost1 = sides[1].army * scale * share
        sides[0].army -= lost0
        sides[1].army -= lost1
        sides[0].armyLost += lost0
        sides[1].armyLost += lost1
        sides[0].armyKilled += lost1
        sides[1].armyKilled += lost0
        sides[share >= 0.5 ? 0 : 1].fightsWon += 1
    }

    mutating func earlyAttack(by attacker: Int, _ events: inout [MatchEvent]) {
        let defender = 1 - attacker
        let defense: Double = switch sides[defender].build {
        case .standard: 1.25
        case .aggressive: 1.0
        case .fastExpand: 0.9
        }
        let attack = power(attacker) * map.rushPower * (0.85 + sides[attacker].skills.judgment / 330)
        let hold = power(defender) * defense * (0.85 + sides[defender].skills.judgment / 330)
        let share0 = attacker == 0 ? fightShare(attack, hold, noise: 0.4) : fightShare(hold, attack, noise: 0.4)
        let share = attacker == 0 ? share0 : 1 - share0
        trade(share: share0, scale: 0.45)
        let name = sides[attacker].player.name, other = sides[defender].player.name
        if share > 0.5 {
            let killed = sides[defender].workers * (share - 0.5) * 1.8
            sides[defender].workers -= killed
            if share > 0.65 { sides[defender].expansion = 0 }
            if sides[defender].bases >= 2, share > 0.65 {
                sides[defender].bases -= 1
                sides[defender].expansion = 0
                say(&events, .score, "\(other)의 앞마당이 무너집니다")
            }
            sides[defender].workersLost += killed
            sides[attacker].workersKilled += killed
            if share > 0.82, rng.chance((share - 0.82) * 2.5) {
                say(&events, .score, "\(name)의 초반 공격이 그대로 들어갑니다! 막을 병력이 없습니다")
                finish(winner: attacker, by: .rush, &events)
                return
            }
            say(&events, .score, killed >= 1
                ? "\(name)의 초반 공격! 일꾼 \(Int(killed.rounded()))기를 잡아냅니다"
                : "\(name)의 초반 공격, \(other.withSubject) 겨우 버팁니다")
        } else {
            say(&events, .score, "\(other), 초반 공격을 막아 냅니다. \(name)의 병력이 녹았습니다")
        }
    }

    mutating func scoutReport(_ events: inout [MatchEvent]) {
        for index in 0..<2 where sides[index].readOpponent {
            say(&events, .play, "\(sides[index].player.name), 정찰 성공. 상대의 빌드를 읽었습니다")
        }
    }

    mutating func harass(_ events: inout [MatchEvent]) {
        for index in 0..<2 {
            let me = sides[index].skills, them = sides[1 - index].skills
            guard sides[index].army > 3, rng.chance((me.control + me.judgment) / 450) else { continue }
            let killed = min(sides[1 - index].workers * 0.3,
                             rng.double(1...3) * (0.7 + me.control / 165) * (1.3 - them.judgment / 200))
            guard killed >= 1 else { continue }
            sides[1 - index].workers -= killed
            sides[1 - index].workersLost += killed
            sides[index].workersKilled += killed
            // 견제를 나간 병력도 조금 잃는다.
            sides[index].army -= 0.5
            sides[index].armyLost += 0.5
            sides[1 - index].armyKilled += 0.5
            say(&events, .play, "\(sides[index].player.name)의 견제, 일꾼 \(Int(killed.rounded()))기를 잡았습니다")
        }
    }

    /// 교전이 났으면 true (같은 틱에 결전을 하지 않는다).
    @discardableResult
    mutating func skirmish(_ events: inout [MatchEvent]) -> Bool {
        guard sides[0].army > 5, sides[1].army > 5 else { return false }
        let power0 = power(0), power1 = power(1)
        let expected = 1 / (1 + pow(power1 / power0, 1.3))
        // 불리한 쪽은 판단이 좋으면 싸움을 피한다.
        let weaker = expected < 0.5 ? 0 : 1
        let weakShare = weaker == 0 ? expected : 1 - expected
        if weakShare < 0.38, rng.chance(sides[weaker].skills.judgment / 130) {
            trade(share: expected, scale: 0.08)
            say(&events, .play, "\(sides[weaker].player.name), 불리한 싸움을 피해 물러납니다")
            return true
        }
        let share = fightShare(power0, power1, noise: 0.5)
        trade(share: share, scale: 0.3)
        let won = share >= 0.5 ? 0 : 1, lost = 1 - won
        let margin = won == 0 ? share : 1 - share
        say(&events, .play, "중앙에서 교전! \(sides[won].player.name.withSubject) 이득을 봅니다 · \(scoreboard)")
        // 크게 이기면 그대로 밀고 들어가 일꾼과 확장을 친다.
        if margin > 0.65 {
            let killed = sides[lost].workers * (margin - 0.6) * 0.6
            sides[lost].workers -= killed
            sides[lost].workersLost += killed
            sides[won].workersKilled += killed
            if margin > 0.75, sides[lost].bases >= 2 {
                sides[lost].bases -= 1
                sides[lost].expansion = 0
                say(&events, .score, "\(sides[won].player.name), 그대로 밀고 들어가 확장 하나를 무너뜨립니다")
            } else {
                say(&events, .play, "\(sides[won].player.name), 상대 일꾼 \(Int(killed.rounded()))기를 잡습니다")
            }
        }
        return true
    }

    /// 한쪽 병력이 압도적이면 결전을 앞당긴다.
    var isLopsided: Bool {
        guard tick >= earliestFinal else { return false }
        let big = max(sides[0].army, sides[1].army), small = min(sides[0].army, sides[1].army)
        return big >= 30 && big >= small * 2.2
    }

    mutating func finalBattle(_ events: inout [MatchEvent]) {
        finalBattles += 1
        say(&events, .inning, "병력이 맞부딪힙니다! \(scoreboard)")
        let share = fightShare(power(0, final: true), power(1, final: true), noise: 0.65)
        trade(share: share, scale: 0.85)
        let won = share >= 0.5 ? 0 : 1, lost = 1 - won
        // 결전이 거듭될수록 끝나기 쉬워진다.
        let margin = [2.0, 1.6, 1.3][min(finalBattles - 1, 2)]
        if finalBattles >= 4 || sides[won].army >= max(8, sides[lost].army * margin)
            || sides[lost].army + sides[lost].workers < 4 {
            say(&events, .score, "\(sides[lost].player.name)의 병력이 녹았습니다. 본진까지 밀립니다")
            finish(winner: won, by: .battle, &events)
            return
        }
        say(&events, .score, "\(sides[won].player.name.withSubject) 이겼지만 끝내지 못합니다. 다시 병력을 모읍니다")
        finalTick = tick + rng.int(8...12)
    }

    mutating func timeout(_ events: inout [MatchEvent]) {
        let won = sides[0].value >= sides[1].value ? 0 : 1
        say(&events, .score, "더 버틸 자원이 없습니다. \(sides[won].player.name.withSubject) 형세를 굳힙니다")
        finish(winner: won, by: .timeout, &events)
    }

    mutating func finish(winner won: Int, by ending: Ending, _ events: inout [MatchEvent]) {
        isFinished = true
        winner = won
        self.ending = ending
        say(&events, .end, "\(sides[1 - won].player.name): GG. \(sides[won].player.name)의 승리!")
    }

    /// 초반(빌드가 갈리는 5분)은 형세가 크게 출렁여서 세지 않는다.
    mutating func trackDeficit() {
        guard tick >= 20 else { return }
        for index in 0..<2 {
            let ratio = sides[index].value / max(sides[1 - index].value, 0.01)
            if ratio < 1 { sides[index].worstDeficit = max(sides[index].worstDeficit, 1 - ratio) }
        }
    }

    func say(_ events: inout [MatchEvent], _ kind: MatchEvent.Kind, _ text: String) {
        events.append(MatchEvent(kind, "\(clockLabel) \(text)"))
    }
}
