import Foundation

/// 구단: 경기 전 방침(훈련, 투수 운용, 라인업, 전술), 팀 이름, 기록 순위.
extension Game {
    // MARK: 경기 전 방침

    public mutating func setTrainingFocus(_ focus: TrainingFocus) {
        teams[userTeamID].focus = focus
    }

    public mutating func setPitchingPolicy(_ policy: PitchingPolicy) {
        teams[userTeamID].policy = policy
    }

    /// 타순을 직접 정한다 (야수 9명). 빈 배열을 넣으면 자동으로 돌아간다.
    public mutating func setLineup(_ ids: [PlayerID]) throws {
        if ids.isEmpty {
            teams[userTeamID].lineupOverride = []
            return
        }
        let chosen = ids.compactMap { players[$0] }
        if sport == .football {
            guard chosen.count == Balance.footballStarters, Set(ids).count == chosen.count,
                  chosen.allSatisfy({ $0.teamID == userTeamID }),
                  chosen.contains(where: { $0.position == .goalkeeper })
            else { throw GameError("골키퍼 1명을 포함해 내 팀 선수 11명을 골라야 합니다.") }
            teams[userTeamID].lineupOverride = ids
            return
        }
        guard chosen.count == 9, Set(ids).count == 9,
              chosen.allSatisfy({ $0.teamID == userTeamID && !$0.isPitcher })
        else { throw GameError("내 팀 야수 9명을 골라야 합니다.") }
        teams[userTeamID].lineupOverride = ids
    }

    public mutating func setNextStarter(_ id: PlayerID?) throws {
        if let id {
            if let player = players[id], player.teamID == userTeamID, player.position == .starter,
               userTeam.gamesPlayed - player.lastStartGame <= Balance.starterRest(userTier) {
                throw GameError("\(player.name)은(는) 아직 쉬어야 합니다. 선발은 등판 뒤 \(Balance.starterRest(userTier))경기를 쉽니다.")
            }
            guard let player = players[id], player.teamID == userTeamID, player.isPitcher else {
                throw GameError("내 팀 투수를 골라야 합니다.")
            }
        }
        teams[userTeamID].starterOverride = id
    }

    public var currentFootballLineup: FootballLineup? {
        FootballLineupBuilder.build(team: userTeam, players: players)
    }

    public mutating func setTactic(_ tactic: Tactic) {
        teams[userTeamID].tactic = tactic
    }

    public mutating func setFormation(_ formation: Formation) {
        teams[userTeamID].formation = formation
    }

    public var currentLineup: Lineup? {
        LineupBuilder.build(team: userTeam, players: players)
    }

    // MARK: 이름 바꾸기

    /// 팀 이름은 언제든 바꿀 수 있다 (다른 팀 이름도).
    public mutating func renameTeam(_ id: TeamID, to newName: String) throws {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { throw GameError("팀 이름을 입력해 주세요.") }
        guard !teams.contains(where: { $0.name == name && $0.id != id }) else {
            throw GameError("이미 있는 팀 이름입니다.")
        }
        teams[id].name = name
    }

    // MARK: 기록 순위

    public struct Leader: Equatable, Sendable {
        public var playerName: String
        public var teamName: String
        public var value: String
        public var isMine: Bool
    }

    public func leaders(_ tier: LeagueTier, count: Int = 5) -> [(title: String, rows: [Leader])] {
        if sport == .football { return footballLeaders(tier, count: count) }
        if sport == .basketball { return basketballLeaders(tier, count: count) }
        let everyone = teams(in: tier).flatMap { roster(of: $0.id) }
        let minPA = max(1, round * 2)
        let minOuts = max(1, round * 2)
        let batters = everyone.filter { !$0.isPitcher && $0.batting.plateAppearances >= minPA }
        let pitchers = everyone.filter { $0.isPitcher && $0.pitching.outs >= minOuts }

        func rows(_ list: [Player], _ text: (Player) -> String) -> [Leader] {
            list.prefix(count).map {
                Leader(
                    playerName: $0.name, teamName: $0.teamID.map { teams[$0].name } ?? "",
                    value: text($0), isMine: isCareer ? isMyPlayer($0.id) : $0.teamID == userTeamID)
            }
        }
        return [
            ("타율", rows(batters.sorted { ($0.batting.average, -$0.id) > ($1.batting.average, -$1.id) }) {
                String(format: "%.3f", $0.batting.average)
            }),
            ("홈런", rows(batters.sorted { ($0.batting.homeRuns, -$0.id) > ($1.batting.homeRuns, -$1.id) }) {
                "\($0.batting.homeRuns)"
            }),
            ("타점", rows(batters.sorted { ($0.batting.runsBattedIn, -$0.id) > ($1.batting.runsBattedIn, -$1.id) }) {
                "\($0.batting.runsBattedIn)"
            }),
            ("다승", rows(pitchers.sorted { ($0.pitching.wins, -$0.id) > ($1.pitching.wins, -$1.id) }) {
                "\($0.pitching.wins)"
            }),
            ("평균자책점", rows(pitchers.filter { $0.position == .starter }
                .sorted { ($0.pitching.era, $0.id) < ($1.pitching.era, $1.id) }) {
                String(format: "%.2f", $0.pitching.era)
            }),
            ("탈삼진", rows(pitchers.sorted { ($0.pitching.strikeouts, -$0.id) > ($1.pitching.strikeouts, -$1.id) }) {
                "\($0.pitching.strikeouts)"
            }),
        ]
    }
}
