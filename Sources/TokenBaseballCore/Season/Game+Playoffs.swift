import Foundation

/// 승강: 정규시즌 순위로 자동 승격·강등을 정하고, 플레이오프를 단계별로 치른다.
///
/// - 야구 (직접 만든 방식): 상위 10위 자동 강등, 하위 1위 자동 승격.
///   하위 2위와 3위가 **승격 와일드카드**(2위 홈, 2위는 1승·3위는 2연승이 필요)를 치르고,
///   이긴 팀이 상위 9위와 **승강 플레이오프**(3전 2선승)를 치른다.
/// - 축구 (잉글랜드 방식): 20팀 리그는 상위 리그의 아래 세 팀 자동 강등, 하위 1위·2위 자동 승격.
///   하위 3~6위가 **승격 플레이오프**를 치른다: 준결승은 홈·원정 두 경기 합산(순위가 낮은 팀이 1차전 홈),
///   결승은 중립 구장 단판. 이긴 한 팀이 승격한다. 상·하위 리그 팀이 맞붙는 승강전은 없다.
///   (10팀 리그로 치르던 시즌은 예전대로 두 팀이 오르내린다: 1위 자동 승격, 2~5위 플레이오프.)
extension PlayoffSeries {
    public var kind: Format { format ?? .bestOfThree }

    public var isDecided: Bool {
        switch kind {
        case .bestOfThree: upperWins >= 2 || lowerWins >= 2
        case .wildcard: upperWins >= 1 || lowerWins >= 2
        case .twoLegs, .single: upperWins + lowerWins >= 1
        }
    }

    /// 이긴 팀. 아직 정해지지 않았으면 nil.
    public var winner: TeamID? {
        guard isDecided else { return nil }
        switch kind {
        case .wildcard: return upperWins >= 1 ? upperTeam : lowerTeam
        default: return upperWins > lowerWins ? upperTeam : lowerTeam
        }
    }

    /// 지금까지 치른 경기 수.
    public var played: Int { kind == .twoLegs ? (legs ?? 0) : upperWins + lowerWins }

    /// 다음 경기의 홈 팀.
    public var nextHome: TeamID {
        switch kind {
        case .bestOfThree: played == 1 ? lowerTeam : upperTeam
        case .twoLegs: played == 0 ? lowerTeam : upperTeam
        case .wildcard, .single: upperTeam
        }
    }

    public var nextAway: TeamID { nextHome == upperTeam ? lowerTeam : upperTeam }

    public var nextLabel: String {
        switch kind {
        case .bestOfThree: "승강 플레이오프 \(played + 1)차전"
        case .wildcard: "승격 와일드카드 \(played + 1)차전"
        case .twoLegs: "승격 플레이오프 준결승 \(played + 1)차전"
        case .single: "승격 플레이오프 결승"
        }
    }

    func involves(_ team: TeamID) -> Bool { upperTeam == team || lowerTeam == team }
}

extension Game {
    /// 승격 자격. CPU 구단은 언제나 자격이 있다.
    /// 내 구단은 야구에서는 승강 플레이오프를 신청해야 하고, 축구에서는 구장 등급(경기장 레벨)을 채워야 한다.
    func canPromote(_ id: TeamID) -> Bool {
        guard teams[id].isUser else { return true }
        switch sport {
        case .football:
            return teams[id].stadiumLevel >= Balance.promotionStadiumLevel(from: teams[id].tier)
        case .baseball, .basketball:
            return appliedForPromotion
        }
    }

    /// 축구: 승격에 필요한 경기장 레벨. 최상위 리그면 nil.
    public var promotionStadiumRequirement: Int? {
        guard sport.usesEnglishPromotion, userTier != .pro else { return nil }
        return Balance.promotionStadiumLevel(from: userTier)
    }

    /// 정규시즌이 끝났을 때: 리그 경계마다 자동 승격·강등과 플레이오프 대진을 정한다.
    mutating func setUpPlayoffs() {
        series = []
        pendingMoves = []
        for upper in LeagueTier.allCases {
            guard let lower = upper.lower else { continue }
            let upperRanked = rankedStandings(upper).map(\.teamID)
            let eligible = rankedStandings(lower).map(\.teamID).filter { canPromote($0) }
            guard upperRanked.count >= 2, let champion = eligible.first else { continue }
            let tenth = upperRanked[upperRanked.count - 1]
            let ninth = upperRanked[upperRanked.count - 2]
            // 상위 리그 최하위는 자동 강등, 하위 리그 1위는 자동 승격.
            pendingMoves.append(TierMove(team: tenth, to: lower))
            pendingMoves.append(TierMove(team: champion, to: upper))

            var contenders = Array(eligible.dropFirst())
            switch sport {
            case .football:
                // 20팀 리그는 2위도 바로 올라가고, 그만큼 한 팀이 더 내려간다.
                let direct = Balance.footballAutoPromotions(teams: upperRanked.count)
                for extra in 1..<direct {
                    guard let next = contenders.first, upperRanked.count - 1 - extra > 0 else { break }
                    contenders.removeFirst()
                    pendingMoves.append(TierMove(team: next, to: upper))
                    pendingMoves.append(TierMove(team: upperRanked[upperRanked.count - 1 - extra], to: lower))
                }
                let moved = pendingMoves.filter { $0.to == lower && upperRanked.contains($0.team) }.count
                guard !contenders.isEmpty, upperRanked.count > moved else { continue }
                // 플레이오프로 한 팀이 더 올라가므로 그 위의 한 팀도 자동 강등이다.
                pendingMoves.append(TierMove(team: upperRanked[upperRanked.count - 1 - moved], to: lower))
                let four = Array(contenders.prefix(4))
                switch four.count {
                case 4:
                    series.append(PlayoffSeries(
                        upperTier: upper, upperTeam: four[0], lowerTeam: four[3], format: .twoLegs, stage: .semi))
                    series.append(PlayoffSeries(
                        upperTier: upper, upperTeam: four[1], lowerTeam: four[2], format: .twoLegs, stage: .semi))
                case 2, 3:
                    series.append(PlayoffSeries(
                        upperTier: upper, upperTeam: four[0], lowerTeam: four[1], format: .single, stage: .final))
                default:
                    pendingMoves.append(TierMove(team: four[0], to: upper))
                }
            case .baseball, .basketball:
                if contenders.count >= 2 {
                    series.append(PlayoffSeries(
                        upperTier: upper, upperTeam: contenders[0], lowerTeam: contenders[1],
                        format: .wildcard, stage: .wildcard))
                } else if let second = contenders.first {
                    series.append(PlayoffSeries(upperTier: upper, upperTeam: ninth, lowerTeam: second))
                }
            }
        }
        for entry in series { resetRotation(entry) }
    }

    /// 야구: 시리즈가 정해지면 두 팀 선발 투수의 휴식을 채워 1차전이 에이스 대결이 되게 한다.
    mutating func resetRotation(_ entry: PlayoffSeries) {
        guard sport == .baseball else { return }
        for team in [entry.upperTeam, entry.lowerTeam] {
            for id in teams[team].roster where players[id]?.position == .starter {
                players[id]?.lastStartGame = -99
            }
        }
    }

    /// 축구 플레이오프 경기의 규칙: 준결승 2차전은 합산으로 승부를 내고, 결승은 중립 구장 단판이다.
    func footballPlayoffRules(_ entry: PlayoffSeries, home: TeamID) -> FootballRules {
        var rules = footballRules(for: .playoff, home: home)
        switch entry.kind {
        case .twoLegs:
            if entry.played == 0 {
                rules.mustHaveWinner = false
            } else {
                // 2차전의 홈은 순위가 높은 팀(upperTeam)이다.
                rules.firstLegHome = entry.upperGoals ?? 0
                rules.firstLegAway = entry.lowerGoals ?? 0
            }
        case .single:
            rules.neutral = true
        default:
            break
        }
        return rules
    }

    /// 플레이오프 한 경기의 결과를 시리즈에 적는다.
    /// `shootoutHomeWon`: 승부차기로 갔으면 홈 팀이 이겼는지.
    mutating func recordPlayoffGame(
        _ index: Int, home: TeamID, homeScore: Int, awayScore: Int, shootoutHomeWon: Bool? = nil
    ) {
        var entry = series[index]
        let upperIsHome = home == entry.upperTeam
        let upperScore = upperIsHome ? homeScore : awayScore
        let lowerScore = upperIsHome ? awayScore : homeScore
        let homeWon = shootoutHomeWon ?? (homeScore > awayScore)

        if entry.kind == .twoLegs {
            entry.upperGoals = (entry.upperGoals ?? 0) + upperScore
            entry.lowerGoals = (entry.lowerGoals ?? 0) + lowerScore
            entry.legs = (entry.legs ?? 0) + 1
            if entry.legs == 2 {
                let upper = entry.upperGoals ?? 0, lower = entry.lowerGoals ?? 0
                let upperWon = upper != lower ? upper > lower : (homeWon == upperIsHome)
                if upperWon { entry.upperWins = 1 } else { entry.lowerWins = 1 }
            }
        } else if homeWon == upperIsHome {
            entry.upperWins += 1
        } else {
            entry.lowerWins += 1
        }
        series[index] = entry
    }

    /// 내 구단이 없는 시리즈를 화면 없이 끝까지 치른다.
    /// (구단이 해체된 상태면 그 자리를 이어받은 CPU 구단의 시리즈도 치른다.)
    mutating func resolveCPUSeries() {
        for index in series.indices where isBankrupt || !series[index].involves(userTeamID) {
            var guardCount = 0
            while !series[index].isDecided, guardCount < 6 {
                guardCount += 1
                let entry = series[index]
                let home = entry.nextHome, away = entry.nextAway
                ensurePlayable(home)
                ensurePlayable(away)
                guard let result = playQuietKnockout(
                    home: home, away: away, kind: .playoff, tier: entry.upperTier, seed: rng.next(),
                    footballRules: sport == .football ? footballPlayoffRules(entry, home: home) : nil)
                else { series[index].upperWins = 2; break }
                recordPlayoffGame(
                    index, home: home, homeScore: result.homeScore, awayScore: result.awayScore,
                    shootoutHomeWon: result.shootout ? result.homeWon : nil)
            }
        }
    }

    /// 지금 단계의 시리즈가 모두 끝났으면 다음 단계를 만들거나 승강을 확정한다.
    mutating func advancePlayoffs() {
        var rounds = 0
        while series.allSatisfy(\.isDecided), rounds < 4 {
            rounds += 1
            var next: [PlayoffSeries] = []
            for upper in LeagueTier.allCases {
                let here = series.filter { $0.upperTier == upper }
                guard !here.isEmpty, let lower = upper.lower else { continue }
                let stage = here[0].stage
                if stage == .wildcard, let winner = here[0].winner {
                    // 와일드카드 승자가 상위 9위와 승강 플레이오프를 치른다.
                    let ranked = rankedStandings(upper).map(\.teamID)
                    let ninth = ranked[ranked.count - 2]
                    next.append(PlayoffSeries(upperTier: upper, upperTeam: ninth, lowerTeam: winner))
                } else if stage == .semi {
                    let winners = here.compactMap(\.winner)
                    let order = rankedStandings(lower).map(\.teamID)
                    let seeded = winners.sorted { (order.firstIndex(of: $0) ?? 0) < (order.firstIndex(of: $1) ?? 0) }
                    if seeded.count >= 2 {
                        next.append(PlayoffSeries(
                            upperTier: upper, upperTeam: seeded[0], lowerTeam: seeded[1], format: .single, stage: .final))
                    } else if let only = seeded.first {
                        pendingMoves.append(TierMove(team: only, to: upper))
                    }
                } else if stage == .final, let winner = here[0].winner {
                    // 축구 결승: 이긴 팀이 승격한다 (그만큼 내려갈 팀은 이미 정해졌다).
                    pendingMoves.append(TierMove(team: winner, to: upper))
                } else if let entry = here.first, entry.lowerWins > entry.upperWins {
                    // 야구 승강 플레이오프: 하위 리그 팀이 이기면 두 팀이 자리를 바꾼다.
                    pendingMoves.append(TierMove(team: entry.lowerTeam, to: upper))
                    pendingMoves.append(TierMove(team: entry.upperTeam, to: lower))
                }
            }
            series = next
            if next.isEmpty {
                finishPlayoffs()
                return
            }
            for entry in next { resetRotation(entry) }
            resolveCPUSeries()
            if let mine = series.first(where: { !$0.isDecided && $0.involves(userTeamID) }) {
                post("\(mine.nextLabel.replacingOccurrences(of: " 1차전", with: ""))에 나갑니다.")
            }
        }
    }
}
