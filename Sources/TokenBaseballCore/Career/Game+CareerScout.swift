import Foundation

/// 내 선수를 지켜보는 다른 구단의 스카우트.
public struct CareerScout: Codable, Equatable, Identifiable, Sendable {
    public var teamID: TeamID
    /// 관심도 (0~100). 기준을 넘으면 이적 기간에 제안이 온다.
    public var interest: Double
    /// 지켜보기 시작한 뒤 내가 뛴 경기 수.
    public var matchesWatched = 0
    /// 마지막 경기에서 관심도가 얼마나 움직였는지 (화면의 ▲▼ 표시용).
    public var lastChange = 0.0
    /// 스카우트가 경기장에 와서 직접 본 횟수.
    public var visits = 0

    public var id: TeamID { teamID }
}

/// 선수 모드: 스카우트. 이적 제안은 "관심이 쌓인 구단"에서 온다.
///
/// - 경기를 뛸 때마다 평점에 따라 관심도가 오르내린다. 그 구단에 가면 주전일수록 조금씩 더 오른다.
/// - 가끔 스카우트가 다음 경기를 직접 보러 온다. 그 경기는 관심도가 두 배로 움직인다.
/// - 관심도가 기준을 넘은 구단은 이적 기간에 제안을 보낸다.
extension Game {
    // MARK: 읽기

    /// 나를 지켜보는 구단들. 관심도가 높은 순서.
    public var careerScouts: [CareerScout] {
        (career?.scouts ?? []).sorted { ($0.interest, -$0.teamID) > ($1.interest, -$1.teamID) }
    }

    /// 다음 경기를 보러 오는 스카우트의 구단. 없으면 nil.
    public var careerScoutVisitor: Team? {
        guard let id = career?.scoutVisit, career?.scouts?.contains(where: { $0.teamID == id }) == true else { return nil }
        return teams[id]
    }

    /// 이 관심도를 넘으면 제안이 온다. 이적을 요청했거나 계약이 끝났으면 문턱이 낮다.
    public var careerScoutOfferThreshold: Double {
        guard let career, let me = players[career.playerID] else { return Balance.careerScoutOfferInterest }
        if me.contract.seasonsLeft <= 0 { return Balance.careerScoutOfferInterestExpired }
        return career.transferRequested ? Balance.careerScoutOfferInterestRequested : Balance.careerScoutOfferInterest
    }

    /// 그 구단이 나를 데려갈 만한지.
    /// - 윗 리그 구단 (두 리그 위까지): 가면 주전이나 주전 경쟁이거나, 유망주로 볼 만큼 어리고 능력이 닿는다.
    /// - 같은 리그 구단: 지금 구단에서 주전이 아닌데 그 구단에 가면 주전이나 주전 경쟁일 때만 (벤치에 묶인 선수의 출구).
    ///   이미 주전인 선수를 같은 리그의 다른 구단이 데려가려 하지는 않는다.
    func careerScoutEligible(_ team: TeamID) -> Bool {
        guard let career, let me = players[career.playerID], let myTeam = me.teamID, team != myTeam else { return false }
        let myTier = teams[myTeam].tier, theirs = teams[team].tier
        let role = careerRole(on: team)
        if theirs == myTier {
            // 계약이 끝난 선수는 지금 주전이어도 데려갈 수 있다 (재계약을 못 받은 선수의 출구).
            let available = careerRole(on: myTeam) != .starter || me.contract.seasonsLeft <= 0
            return role != .prospect && available
        }
        // 위로는 두 리그까지만 본다. 6부 선수를 1부 구단이 지켜보지는 않는다. 1부 선수는 1부 구단만 본다.
        let gap = myTier.rawValue - theirs.rawValue
        guard (1...Balance.careerScoutTierReach).contains(gap) else { return false }
        if role != .prospect { return true }
        // 유망주로 데려가는 것은 바로 위 리그만이고, 이름이 알려진 어린 선수여야 한다.
        // 두 리그를 한 번에 뛰어오르려면 그 구단에서 곧바로 주전을 다툴 실력이어야 한다.
        return gap == 1 && me.age <= 23 && career.fame >= Balance.careerFameCap(myTier) * 0.8
            && me.ability >= Balance.abilityRange(theirs).lowerBound - 8
    }

    // MARK: 경기 뒤

    /// 경기가 끝난 뒤 스카우트들의 관심도를 고친다. 알릴 것이 있으면 돌려준다.
    /// 내가 나오지 않은 경기는 아무것도 바꾸지 않는다 (보러 온 스카우트는 헛걸음한다).
    mutating func updateCareerScouts(
        _ career: inout Career, me: Player, performance: CareerPerformance?, kind: MatchKind
    ) -> [String] {
        var lines: [String] = []
        var scouts = career.scouts ?? []
        let visitor = career.scoutVisit
        career.scoutVisit = nil
        guard !career.isFreeAgent, me.teamID != nil else {
            career.scouts = nil
            return []
        }

        if let performance {
            // 명성과 같은 기준을 쓴다: 야구는 6.5, 축구와 농구는 6.3. 그보다 조금 아래부터 관심이 오른다.
            let baseline = (me.position.sport == .baseball ? 6.5 : 6.3) - Balance.careerScoutBaselineSlack
            // 선발 투수는 나오는 경기가 적어서 한 경기가 더 크게 반영된다.
            let rarity = me.position == .starter ? Balance.careerScoutStarterPitcher : 1.0
            let weight = kind == .friendly ? 0.5 : 1.0
            for index in scouts.indices {
                let team = scouts[index].teamID
                var change = (performance.rating - baseline) * Balance.careerScoutPerRating * rarity
                // 그 구단에 가면 주전일수록 관심이 꾸준히 쌓인다 (벤치에 묶인 선수의 출구).
                switch careerRole(on: team) {
                case .starter: change += Balance.careerScoutFitStarter
                case .rotation: change += Balance.careerScoutFitRotation
                case .prospect: break
                }
                change += career.fame / 100
                change *= weight
                let watched = visitor == team
                if watched {
                    change *= Balance.careerScoutVisitMultiplier
                    scouts[index].visits += 1
                }
                let before = scouts[index].interest
                scouts[index].interest = clamp(before + change, 0, 100)
                scouts[index].lastChange = scouts[index].interest - before
                scouts[index].matchesWatched += 1
                if watched {
                    let moved = Int(scouts[index].lastChange.rounded())
                    let verdict = performance.rating >= 7 ? "깊은 인상을 받았습니다" : performance.rating >= 6.2 ? "무난하게 봤습니다" : "실망한 눈치입니다"
                    lines.append("\(teams[team].name) 스카우트가 경기를 지켜봤습니다: \(verdict) (관심도 \(moved >= 0 ? "+" : "")\(moved))")
                }
            }
        } else if let visitor, scouts.contains(where: { $0.teamID == visitor }) {
            lines.append("\(teams[visitor].name) 스카우트가 왔지만 출전하지 않아 보여 주지 못했습니다.")
        }

        // 관심이 식었거나 더는 데려갈 수 없는 구단은 떠난다.
        for scout in scouts where scout.interest <= 0 || !careerScoutEligible(scout.teamID) {
            lines.append(scout.interest <= 0
                ? "\(teams[scout.teamID].name) 스카우트가 관심을 거뒀습니다."
                : "\(teams[scout.teamID].name) 스카우트가 떠났습니다 (이제 그 구단에는 맞는 자리가 없습니다).")
        }
        scouts.removeAll { $0.interest <= 0 || !careerScoutEligible($0.teamID) }

        // 새 스카우트: 명성이 높을수록, 방금 잘했을수록, 이적을 요청했거나 계약이 끝났을수록 잘 온다.
        // 자리가 다 찼으면, 가면 주전인 구단만 올 수 있다: 관심이 가장 낮은 "유망주로 보는" 구단을 밀어낸다.
        let full = scouts.count >= Balance.careerScoutMax
        let weakest = scouts.indices
            .filter { careerRole(on: scouts[$0].teamID) != .starter }
            .min { (scouts[$0].interest, scouts[$0].teamID) < (scouts[$1].interest, scouts[$1].teamID) }
        if !full || weakest != nil, performance != nil || me.contract.seasonsLeft <= 0 {
            var chance = Balance.careerScoutArrival + career.fame / 250
            if let performance, performance.rating >= 7 { chance += 0.12 }
            if career.transferRequested { chance += 0.3 }
            if me.contract.seasonsLeft <= 0 { chance += 0.4 }
            if rng.chance(min(0.9, chance)) {
                let watching = Set(scouts.map(\.teamID))
                let candidates = teams.map(\.id).filter {
                    !watching.contains($0) && careerScoutEligible($0) && (!full || careerRole(on: $0) == .starter)
                }
                if !candidates.isEmpty {
                    if full, let weakest {
                        lines.append("\(teams[scouts[weakest].teamID].name) 스카우트가 다른 구단에 밀려 떠났습니다.")
                        scouts.remove(at: weakest)
                    }
                    let myTier = teams[userTeamID].tier
                    // 윗 리그 구단이 더 자주 온다. 가면 주전인 구단도 눈여겨본다.
                    let pick = candidates[rng.weighted(candidates.map { id in
                        (teams[id].tier < myTier ? 2.0 : 1.0) * (careerRole(on: id) == .starter ? 1.5 : 1.0)
                    })]
                    let start = 20 + career.fame / 4 + rng.double(0...15) + (careerRole(on: pick) == .starter ? 8 : 0)
                    scouts.append(CareerScout(teamID: pick, interest: min(60, start)))
                    lines.append("\(teams[pick].tier.displayName) \(teams[pick].name)의 스카우트가 지켜보기 시작했습니다.")
                }
            }
        }

        // 다음 경기를 직접 보러 올 스카우트.
        if !scouts.isEmpty, rng.chance(Balance.careerScoutVisitChance) {
            let pick = scouts[rng.weighted(scouts.map { 20 + $0.interest })].teamID
            career.scoutVisit = pick
            lines.append("다음 경기에 \(teams[pick].name) 스카우트가 직접 보러 옵니다.")
        }
        career.scouts = scouts.isEmpty ? nil : scouts
        return lines
    }

    /// 제안을 보낼 스카우트: 관심도가 문턱을 넘었고 지금도 데려갈 만한 구단 가운데 관심이 가장 높은 곳.
    func careerScoutReadyToOffer() -> CareerScout? {
        let threshold = careerScoutOfferThreshold
        return careerScouts.first { $0.interest >= threshold && careerScoutEligible($0.teamID) }
    }

    /// 제안을 거절했거나, 답하지 않았거나, 협상이 깨졌을 때: 그 구단의 스카우트는 떠난다.
    /// (다시 눈에 띄면 처음부터 지켜보기 시작한다. 같은 구단이 매 경기 다시 제안하지 않는다.)
    mutating func coolCareerScout(_ team: TeamID) {
        guard var scouts = career?.scouts else { return }
        scouts.removeAll { $0.teamID == team }
        career?.scouts = scouts.isEmpty ? nil : scouts
        if career?.scoutVisit == team { career?.scoutVisit = nil }
    }

    /// 구단을 옮겼거나 무소속이 됐거나 은퇴했다: 지켜보던 스카우트는 모두 떠난다.
    mutating func clearCareerScouts() {
        career?.scouts = nil
        career?.scoutVisit = nil
    }

    /// 새 시즌: 리그가 달라져 더는 데려갈 수 없는 구단은 떠나고, 남은 관심은 조금 식는다.
    mutating func refreshCareerScoutsForSeason() {
        guard var scouts = career?.scouts else { return }
        scouts.removeAll { !careerScoutEligible($0.teamID) }
        for index in scouts.indices {
            scouts[index].interest *= Balance.careerScoutSeasonKeep
            scouts[index].lastChange = 0
        }
        career?.scouts = scouts.isEmpty ? nil : scouts
        if let visit = career?.scoutVisit, !scouts.contains(where: { $0.teamID == visit }) { career?.scoutVisit = nil }
    }

    /// 화면 확인용: 스카우트 몇 명을 붙인다.
    public mutating func generateDemoCareerScouts() {
        guard career != nil else { return }
        let candidates = teams.map(\.id).filter { careerScoutEligible($0) }
        var scouts: [CareerScout] = []
        for (index, team) in candidates.prefix(3).enumerated() {
            var scout = CareerScout(teamID: team, interest: [74, 46, 18][index])
            scout.matchesWatched = [12, 6, 2][index]
            scout.lastChange = [5, -2, 3][index]
            scout.visits = [2, 1, 0][index]
            scouts.append(scout)
        }
        career?.scouts = scouts.isEmpty ? nil : scouts
        career?.scoutVisit = scouts.dropFirst().first?.teamID
    }
}
