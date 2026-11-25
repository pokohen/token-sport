import Foundation

/// e스포츠 개인 대회 (→ docs/10-esports.md "개인 리그"). 다른 종목의 컵대회 자리에 들어간다.
/// 팀 리그는 구단이 정하지만, 개인 대회는 내 이름값(팬 수)으로 나간다. 여섯 단계이고, 정해진 라운드가 지나면 열린다.
/// 대회는 화면 없이 치르고 결과가 소식으로 나온다.
public enum DuelTournament: Int, Codable, CaseIterable, Comparable, Sendable {
    case world = 1, asia, korea, national, city, pcBang

    public static func < (lhs: DuelTournament, rhs: DuelTournament) -> Bool { lhs.rawValue < rhs.rawValue }

    /// 대회 이름 (PC방 대회와 시장배는 그때그때 이름이 붙는다).
    public var baseName: String {
        switch self {
        case .pcBang: "동네 PC방 대회"
        case .city: "시장배 아마추어 대회"
        case .national: "전국 e스포츠 선수권"
        case .korea: "코리아 그랜드 리그"
        case .asia: "아시아 마스터즈"
        case .world: "월드 그랜드 파이널"
        }
    }

    /// 나갈 수 있는 팬 수.
    public var requiredFans: Int {
        switch self {
        case .pcBang: 100
        case .city: 1_000
        case .national: 10_000
        case .korea: 100_000
        case .asia: 1_000_000
        case .world: 10_000_000
        }
    }

    /// 본선에 나오는 선수 수.
    public var entrants: Int {
        switch self {
        case .city, .national: 32
        case .pcBang, .korea, .asia, .world: 16
        }
    }

    /// 리그 몇 라운드를 마친 뒤에 열리는지 (36라운드 시즌).
    public var afterRounds: [Int] {
        switch self {
        case .pcBang: [4, 10, 16, 22, 28, 34]
        case .city: [7, 25]
        case .national: [13, 31]
        case .korea: [19]
        case .asia: [27]
        case .world: [35]
        }
    }

    /// 대회에 나오는 다른 선수의 능력 (코리아 그랜드 리그부터는 세계의 실제 선수가 나온다).
    var fieldAbility: ClosedRange<Double> {
        switch self {
        case .pcBang: 18...38
        case .city: 25...48
        case .national: 35...60
        case .korea: 55...80
        case .asia: 62...88
        case .world: 70...95
        }
    }

    /// 한 판을 이길 때마다 느는 팬. 우승하면 두 배를 더 받는다.
    var fansPerWin: Int {
        switch self {
        case .pcBang: 40
        case .city: 400
        case .national: 3_000
        case .korea: 25_000
        case .asia: 200_000
        case .world: 1_500_000
        }
    }

    /// 우승 상금 (훈련 포인트). 준우승은 절반, 4강은 4분의 1.
    var prize: Int {
        switch self {
        case .pcBang: 300_000
        case .city: 1_500_000
        case .national: 5_000_000
        case .korea: 20_000_000
        case .asia: 60_000_000
        case .world: 150_000_000
        }
    }

    /// 한 단계 위 대회.
    public var upper: DuelTournament? { DuelTournament(rawValue: rawValue - 1) }
}

/// 내가 나간 개인 대회 하나의 결과.
public struct DuelEventRecord: Codable, Equatable, Sendable {
    public var season: Int
    public var tournament: DuelTournament
    public var name: String
    /// "우승", "준우승", "4강", "16강" …
    public var finish: String
    public var won: Bool
    /// 이 대회의 우승자.
    public var champion: String
}

extension Game {
    // MARK: 출전 자격

    /// 지금 이 대회에 나갈 수 있는지: 팬 수가 모자라도, 바로 아래 대회에서 우승해 초대받았으면 나간다.
    public func canEnterDuel(_ tournament: DuelTournament) -> Bool {
        guard let career, let fans = career.fans else { return false }
        return fans >= tournament.requiredFans || career.duelInvite == tournament.rawValue
    }

    /// 이 대회에 나갈지: 자격이 있고, 두 단계 위 대회에 나갈 만큼 크지 않을 때 (큰 선수는 동네 대회에 나가지 않는다).
    func entersDuel(_ tournament: DuelTournament) -> Bool {
        guard canEnterDuel(tournament), let fans = career?.fans else { return false }
        if let higher = tournament.upper?.upper, fans >= higher.requiredFans { return false }
        return true
    }

    /// 다음에 열리는 개인 대회 (화면 안내용).
    public var nextDuelTournament: (tournament: DuelTournament, round: Int, eligible: Bool)? {
        guard sport == .duel, phase == .regular else { return nil }
        let upcoming = DuelTournament.allCases.flatMap { tournament in tournament.afterRounds.map { (tournament, $0) } }
            .filter { $0.1 > round }
            .sorted { ($0.1, $0.0.rawValue) < ($1.1, $1.0.rawValue) }
        guard let first = upcoming.first(where: { entersDuel($0.0) }) ?? upcoming.first else { return nil }
        return (first.0, first.1, entersDuel(first.0))
    }

    // MARK: 대회 열기

    /// 리그 경기를 하나 마친 뒤: 이 라운드에 열리는 개인 대회를 치른다.
    mutating func runDuelTournamentsIfDue() {
        guard isCareer, sport == .duel, let career, !career.retired, !career.isFreeAgent else { return }
        for tournament in DuelTournament.allCases where tournament.afterRounds.contains(round) {
            guard entersDuel(tournament) else { continue }
            playDuelTournament(tournament)
        }
    }

    func duelTournamentName(_ tournament: DuelTournament, seed: UInt64) -> String {
        var rng = SeededRNG(seed: seed)
        switch tournament {
        case .pcBang: return "\(rng.pick(NameGenerator.pcBangWords)) PC방 배"
        case .city:
            let city = (players[career?.playerID ?? -1]?.origin.split(separator: " ").first).map(String.init) ?? "서울"
            return "\(city) 시장배 아마추어 대회"
        default: return tournament.baseName
        }
    }

    /// 대회에 나오는 다른 선수들. 코리아 그랜드 리그부터는 세계에서 가장 잘하는 선수들이 나오고,
    /// 아시아와 월드 대회에는 해외 선수가 절반 섞인다.
    func duelField(_ tournament: DuelTournament, count: Int, rng: inout SeededRNG) -> [(PlayerID, DuelPlayer)] {
        var field: [(PlayerID, DuelPlayer)] = []
        let me = career?.playerID
        if tournament <= .korea {
            let local = tournament == .korea ? count : count / 2
            let best = players.values.filter { $0.position.sport == .duel && $0.id != me && $0.teamID != nil }
                .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
                .prefix(local)
            field += best.map { ($0.id, DuelPlayer($0)) }
        }
        var next = -1
        while field.count < count {
            let ability = rng.double(tournament.fieldAbility)
            let race = rng.pick(DuelRace.allCases)
            var skills = DuelSkills.uniform(ability)
            for key in DuelSkills.keys { skills[keyPath: key] = clamp(ability + rng.gaussian() * 5, 1, 99) }
            let name = tournament <= .asia ? NameGenerator.foreignName(&rng) : NameGenerator.playerName(&rng, sport: .duel)
            field.append((next, DuelPlayer(name: name, race: race, skills: skills, style: rng.pick(DuelStyle.allCases))))
            next -= 1
        }
        return field
    }

    /// 대회 하나를 화면 없이 치른다: 한 판은 3전 2선승, 결승은 5전 3선승.
    mutating func playDuelTournament(_ tournament: DuelTournament) {
        guard var career, let me = players[career.playerID], let mine = duelPlayer(me.id) else { return }
        var local = SeededRNG(seed: rng.next())
        let name = duelTournamentName(tournament, seed: local.next())
        var alive = local.shuffled([(me.id, mine)] + duelField(tournament, count: tournament.entrants - 1, rng: &local))
        var wins = 0
        var lostTo: String?
        var path: [String] = []
        while alive.count > 1 {
            let isFinal = alive.count == 2
            let roundName = isFinal ? "결승" : alive.count == 4 ? "4강" : "\(alive.count)강"
            var winners: [(PlayerID, DuelPlayer)] = []
            for index in stride(from: 0, to: alive.count - 1, by: 2) {
                let (homeID, home) = alive[index], (awayID, away) = alive[index + 1]
                var match = DuelMatch(
                    home: .init(teamID: nil, name: home.name, lineup: [homeID], players: [homeID: home]),
                    away: .init(teamID: nil, name: away.name, lineup: [awayID], players: [awayID: away]),
                    bestOf: isFinal ? 5 : 3, isFinal: isFinal, seed: local.next())
                match.runToEnd()
                let winner = match.homeWon ? alive[index] : alive[index + 1]
                winners.append(winner)
                if homeID == me.id || awayID == me.id {
                    let iWon = winner.0 == me.id
                    let opponent = homeID == me.id ? away : home
                    let score = homeID == me.id ? "\(match.home.sets):\(match.away.sets)" : "\(match.away.sets):\(match.home.sets)"
                    path.append("\(roundName) \(iWon ? "승" : "패") \(score) (\(opponent.name), \(opponent.race.label))")
                    if iWon { wins += 1 } else { lostTo = opponent.name }
                }
            }
            alive = winners
        }
        let champion = alive.first
        let won = champion?.0 == me.id
        let rounds = Int(log2(Double(tournament.entrants)))
        let finish: String = {
            if won { return "우승" }
            let reached = tournament.entrants >> wins
            return reached == 2 ? "준우승" : reached == 4 ? "4강" : "\(reached)강"
        }()

        var gained = tournament.fansPerWin * wins
        if won { gained += tournament.fansPerWin * 2 }
        career.fans = (career.fans ?? 0) + gained
        let prize = won ? tournament.prize : wins == rounds - 1 ? tournament.prize / 2 : wins == rounds - 2 ? tournament.prize / 4 : 0
        if prize > 0 { funds.earn(price(prize), .prize) }
        if career.duelInvite == tournament.rawValue { career.duelInvite = nil }
        if won {
            var titles = career.duelWins ?? Array(repeating: 0, count: DuelTournament.allCases.count)
            titles[tournament.rawValue - 1] += 1
            career.duelWins = titles
            career.awards.append("\(season)시즌 \(name) 우승")
            // 바로 위 대회 한 번은 팬이 모자라도 초대받는다.
            if let upper = tournament.upper, (career.fans ?? 0) < upper.requiredFans { career.duelInvite = upper.rawValue }
        }
        career.duelEvents = Array(((career.duelEvents ?? []) + [DuelEventRecord(
            season: season, tournament: tournament, name: name, finish: finish, won: won,
            champion: champion?.1.name ?? "")]).suffix(60))
        let titleBefore = duelTitle
        self.career = career
        syncDuelFame()

        var line = "\(name) \(finish)"
        if !won, let lostTo { line += " (\(lostTo)에게 졌습니다)" }
        line += ". 팬 +\(fansText(gained))"
        if prize > 0 { line += ", 상금 \(fundsText(price(prize)))" }
        post(line)
        if !path.isEmpty { post("\(name): \(path.joined(separator: " → "))") }
        if won, let upper = tournament.upper, self.career?.duelInvite == upper.rawValue {
            post("\(upper.baseName)에 초대받았습니다. 팬이 모자라도 다음 대회 한 번은 나갑니다.")
        }
        if let title = duelTitle, title != titleBefore { post("이제 '\(title)'(이)라 불립니다.") }
    }

    // MARK: 칭호

    /// 우승한 가장 큰 대회와 그 대회 이상의 우승 횟수, 그리고 팬 수로 정한 칭호 (→ docs/10-esports.md "칭호").
    public var duelTitle: String? {
        guard let career, let fans = career.fans else { return nil }
        let wins = career.duelWins ?? []
        guard let best = DuelTournament.allCases.sorted().first(where: { wins.count >= $0.rawValue && wins[$0.rawValue - 1] > 0 })
        else {
            return fans >= 100_000 ? "무관의 스타" : nil
        }
        let count = DuelTournament.allCases.filter { $0 <= best }.reduce(0) { $0 + wins[$1.rawValue - 1] }
        let city = (players[career.playerID]?.origin.split(separator: " ").first).map(String.init) ?? "고향"
        let title: String = switch best {
        case .pcBang: count >= 3 ? "PC방의 전설" : "동네 고수"
        case .city: count >= 3 ? "\(city)의 자존심" : "\(city) 최강"
        case .national: count >= 3 ? "전국 최강" : "전국구"
        case .korea: count >= 5 ? "황제" : count >= 3 ? "왕" : "챔피언"
        case .asia: count >= 3 ? "아시아의 지배자" : "아시아의 별"
        case .world: count >= 5 ? "살아 있는 전설" : count >= 3 ? "세계의 왕" : "세계 챔피언"
        }
        if fans >= 10_000_000 { return "모두의 \(title)" }
        if fans >= 1_000_000 { return "국민 \(title)" }
        if fans * 10 < best.requiredFans { return "숨은 \(title)" }
        return title
    }
}
