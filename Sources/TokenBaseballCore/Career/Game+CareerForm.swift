import Foundation

/// 선수 모드: 그날의 컨디션.
public enum CareerCondition: String, Codable, CaseIterable, Sendable {
    case best, good, normal, poor, worst

    public var label: String {
        switch self {
        case .best: "최상"
        case .good: "좋음"
        case .normal: "보통"
        case .poor: "나쁨"
        case .worst: "최악"
        }
    }

    /// 그 경기에서 내 능력치에 곱해지는 변화 (0.03 = +3%).
    public var modifier: Double {
        switch self {
        case .best: 0.06
        case .good: 0.03
        case .normal: 0
        case .poor: -0.03
        case .worst: -0.06
        }
    }

    /// 나올 비율 (합 100).
    var weight: Double {
        switch self {
        case .best: 10
        case .good: 25
        case .normal: 40
        case .poor: 20
        case .worst: 5
        }
    }
}

/// 선수 모드: 라이벌. 같은 리그의 다른 구단에서 나와 비슷한 선수.
public struct CareerRival: Codable, Equatable, Sendable {
    public var playerID: PlayerID
    /// 맞대결(라이벌 구단과의 경기에서 둘 다 뛴 날) 전적: 평점이 높은 쪽이 이긴다.
    public var wins = 0
    public var losses = 0
    public var draws = 0
    /// 마지막 맞대결 한 줄.
    public var lastMeeting: String?
}

extension Game {
    // MARK: 컨디션과 기세

    /// 다음 경기의 컨디션. 아직 정해지지 않았으면 보통.
    public var careerCondition: CareerCondition { career?.condition ?? .normal }

    /// 연속 활약(+)이나 연속 부진(−) 경기 수.
    public var careerStreak: Int { career?.streak ?? 0 }

    /// 기세가 능력치에 주는 변화: 세 경기 연속 활약이면 오르고, 세 경기 연속 부진이면 내린다.
    public var careerMomentum: Double {
        if careerStreak >= Balance.careerStreakLength { return Balance.careerMomentum }
        if careerStreak <= -Balance.careerStreakLength { return -Balance.careerMomentum }
        return 0
    }

    /// 다음 경기에서 내 능력치에 곱해지는 변화 (컨디션 + 기세).
    public var careerFormModifier: Double { careerCondition.modifier + careerMomentum }

    /// 기세를 한 줄로. 없으면 nil.
    public var careerStreakText: String? {
        if careerStreak >= Balance.careerStreakLength { return "\(careerStreak)경기 연속 활약" }
        if careerStreak <= -Balance.careerStreakLength { return "\(-careerStreak)경기 연속 부진" }
        return nil
    }

    /// 연속 기록의 이름 (포지션마다 다르다).
    public var careerRunLabel: String {
        guard let me = myPlayer else { return "연속 기록" }
        switch me.position {
        case .goalkeeper: return "연속 무실점"
        case _ where me.position.sport == .basketball: return "연속 두 자릿수 득점"
        case _ where me.position.sport == .football: return "연속 공격포인트"
        case _ where me.isPitcher: return "연속 무자책"
        default: return "연속 안타"
        }
    }

    /// 야구: 경기 엔진에 넘어간 내 선수의 능력치에 컨디션과 기세를 반영한다.
    func applyCareerForm(_ state: inout MatchState, userIsHome: Bool) {
        guard let career else { return }
        let factor = 1 + careerFormModifier
        guard factor != 1 else { return }
        func scale(_ value: inout Double) { value = clamp(value * factor, 1, 99) }
        var side = userIsHome ? state.home : state.away
        if let index = side.batters.firstIndex(where: { $0.playerID == career.playerID }) {
            scale(&side.batters[index].contact); scale(&side.batters[index].power); scale(&side.batters[index].eye)
            scale(&side.batters[index].speed); scale(&side.batters[index].fielding); scale(&side.batters[index].arm)
        }
        if let index = side.pitchers.firstIndex(where: { $0.playerID == career.playerID }) {
            scale(&side.pitchers[index].stuff); scale(&side.pitchers[index].control); scale(&side.pitchers[index].breaking)
        }
        if userIsHome { state.home = side } else { state.away = side }
    }

    /// 축구: 내 선수의 능력치에 컨디션과 기세를 반영하고, 상대에 라이벌이 있으면 그 선수도 세부 기록을 남기게 한다.
    func applyCareerForm(_ match: inout FootballMatch, userIsHome: Bool) {
        guard let career else { return }
        let factor = 1 + careerFormModifier
        var mine = userIsHome ? match.home : match.away
        var theirs = userIsHome ? match.away : match.home
        if factor != 1, let index = mine.players.firstIndex(where: { $0.playerID == career.playerID }) {
            func scale(_ value: inout Double) { value = clamp(value * factor, 1, 99) }
            scale(&mine.players[index].shooting); scale(&mine.players[index].passing)
            scale(&mine.players[index].dribbling); scale(&mine.players[index].tackling)
            scale(&mine.players[index].speed); scale(&mine.players[index].physical); scale(&mine.players[index].keeping)
        }
        if let rival = career.rival, let index = theirs.players.firstIndex(where: { $0.playerID == rival.playerID }) {
            theirs.players[index].detail = FootballDetail()
        }
        if userIsHome { match.home = mine; match.away = theirs } else { match.away = mine; match.home = theirs }
    }

    /// 경기 뒤: 기세와 연속 기록을 고치고, 다음 경기의 컨디션을 뽑는다. 알릴 것이 있으면 돌려준다.
    mutating func updateCareerForm(_ career: inout Career, performance: CareerPerformance?, kind: MatchKind) -> [String] {
        var lines: [String] = []
        if let performance, kind != .friendly {
            let before = career.streak ?? 0
            var streak = 0
            if performance.rating >= Balance.careerStreakGood { streak = max(before, 0) + 1 }
            else if performance.rating <= Balance.careerStreakBad { streak = min(before, 0) - 1 }
            career.streak = streak
            if streak == Balance.careerStreakLength { lines.append("기세가 올랐습니다: \(streak)경기 연속 활약 (능력 +\(Int(Balance.careerMomentum * 100))%)") }
            if streak == -Balance.careerStreakLength { lines.append("슬럼프입니다: \(-streak)경기 연속 부진 (능력 −\(Int(Balance.careerMomentum * 100))%)") }
            if before <= -Balance.careerStreakLength, streak >= 0 { lines.append("슬럼프에서 벗어났습니다.") }
            if let scored = performance.scored {
                let run = scored ? (career.run ?? 0) + 1 : 0
                career.run = run
                if run > (career.bestRun ?? 0) {
                    career.bestRun = run
                    if run >= 5 { lines.append("\(careerRunLabel) \(run)경기: 개인 최고 기록") }
                }
            }
        }
        let next = CareerCondition.allCases[rng.weighted(CareerCondition.allCases.map(\.weight))]
        career.condition = next
        if next != .normal { lines.append("다음 경기 컨디션: \(next.label)") }
        return lines
    }

    // MARK: 라이벌

    public var careerRival: Player? { career?.rival.flatMap { players[$0.playerID] } }

    /// 라이벌로 삼을 수 있는 선수인지: 같은 리그의 다른 구단, 같은 역할.
    private func isRivalCandidate(_ other: Player, for me: Player) -> Bool {
        guard other.id != me.id, let team = other.teamID, team != userTeamID,
              teams[team].tier == userTier else { return false }
        if me.position.sport != .baseball { return other.position == me.position }
        if me.isPitcher { return other.isPitcher && (other.position == .starter) == (me.position == .starter) }
        return !other.isPitcher && other.position.sport == me.position.sport
    }

    /// 라이벌이 없거나 더는 맞지 않으면(리그가 달라졌다, 은퇴했다, 같은 구단이 됐다) 새로 정한다.
    /// 나보다 조금 나은 선수를 고른다. 바뀌었으면 알리는 한 줄을 돌려준다.
    /// `seasonStart`: 새 시즌에는 내가 훌쩍 앞서 버린 라이벌도 바꾼다.
    @discardableResult
    mutating func refreshCareerRival(seasonStart: Bool = false) -> String? {
        guard let career, !career.retired, !career.isFreeAgent, let me = players[career.playerID] else { return nil }
        if let rival = career.rival, let player = players[rival.playerID], isRivalCandidate(player, for: me),
           !(seasonStart && me.ability - player.ability > Balance.careerRivalOutgrown) { return nil }
        let target = me.ability + Balance.careerRivalEdge
        // 능력이 비슷한 선수 가운데 또래를 먼저 고른다 (나이 차이 한 살이 능력 0.4만큼).
        func distance(_ other: Player) -> Double {
            abs(other.ability - target) + Double(max(0, other.age - me.age - Balance.careerRivalAgeGap)) * 0.4
        }
        let candidates = players.values.filter { isRivalCandidate($0, for: me) && $0.id != career.rival?.playerID }
        guard let pick = candidates.min(by: { (distance($0), $0.id) < (distance($1), $1.id) }) else {
            self.career?.rival = nil
            return nil
        }
        self.career?.rival = CareerRival(playerID: pick.id)
        let club = pick.teamID.map { teams[$0].name } ?? ""
        return "새 라이벌: \(club)의 \(pick.name) (\(pick.position.label), 능력 \(Int(pick.ability)))"
    }

    /// 라이벌 구단과의 경기에서 둘 다 뛰었으면 평점으로 승부를 가린다. 이기면 명성이 조금 오른다.
    func settleCareerRival(_ career: inout Career, mine: CareerPerformance?, rival: CareerPerformance?) -> [String] {
        guard var record = career.rival, let mine, let rival, let player = players[record.playerID] else { return [] }
        let gap = mine.rating - rival.rating
        let score = "\(String(format: "%.1f", mine.rating)) 대 \(String(format: "%.1f", rival.rating))"
        let line: String
        if gap > 0.05 {
            record.wins += 1
            let cap = Balance.careerFameCap(userTier)
            career.fame = min(max(career.fame, cap), career.fame + Balance.careerRivalFame)
            line = "라이벌 \(player.name)과(와)의 맞대결에서 이겼습니다 (평점 \(score))"
        } else if gap < -0.05 {
            record.losses += 1
            line = "라이벌 \(player.name)과(와)의 맞대결에서 졌습니다 (평점 \(score))"
        } else {
            record.draws += 1
            line = "라이벌 \(player.name)과(와)의 맞대결은 비겼습니다 (평점 \(score))"
        }
        record.lastMeeting = line
        career.rival = record
        return [line]
    }

    // MARK: 토큰으로 치른 경기의 실전 경험

    /// 토큰으로 사서 치른 경기에서 얻는 능력: 평점이 좋을수록 많이 오른다. 한계(잠재력)는 넘지 않는다.
    static func careerExtraMatchGain(rating: Double) -> Double {
        clamp(Balance.careerExtraMatchBase + (rating - 6) * Balance.careerExtraMatchPerRating,
              Balance.careerExtraMatchBase, Balance.careerExtraMatchMax)
    }

    /// 실전 경험을 능력치에 반영한다. 실제로 오른 능력(CA)을 돌려준다.
    mutating func applyCareerExtraMatchGain(rating: Double) -> Double {
        guard let career, var me = players[career.playerID] else { return 0 }
        let gain = min(Self.careerExtraMatchGain(rating: rating), max(0, me.potential - me.ability))
        guard gain > 0 else { return 0 }
        let before = me.ability
        for key in careerTrainableKeys { me.attributes[key] = min(99, me.attributes[key] + gain) }
        players[me.id] = me
        return me.ability - before
    }
}
