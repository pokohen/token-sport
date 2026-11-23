import Foundation

/// 선수 모드: 구단을 운영하는 대신 선수 한 명(야구 타자·투수, 축구 선수)이 되어 커리어를 보낸다.
///
/// 세계는 구단 모드와 똑같이 돌아가고, 60개 구단이 모두 CPU 구단이다.
/// `userTeamID`는 "내 선수가 뛰는 구단"을 가리키고, 그 구단의 경기가 중계된다.
extension Game {
    public var isCareer: Bool { career != nil }

    /// 내 선수. 은퇴했으면 nil.
    public var myPlayer: Player? { career.flatMap { players[$0.playerID] } }

    func isMyPlayer(_ id: PlayerID) -> Bool { career?.playerID == id }

    /// 내 선수의 재능 등급 (성장 한계를 대강 알려 준다).
    public var careerTalent: CareerTalent? { myPlayer.map { CareerTalent(potential: $0.potential) } }

    /// 선수 모드에는 기준이 될 "내 구단"이 없으므로 맞춰주기를 끈다.
    var effectiveRubberBand: RubberBand { isCareer ? .off : settings.rubberBand }

    // MARK: 시작

    /// 새 선수 모드: 6개 리그 60팀을 모두 CPU 구단으로 만들고, 내 선수를 6부 구단에 입단시킨다.
    public static func newCareer(setup: CareerSetup, now: Date, seed: UInt64) -> Game {
        newCareer(setup: setup, now: now, seed: seed, leagueSize: Balance.teamsPerLeague(setup.sport))
    }

    /// `leagueSize`: 리그마다 몇 팀인지. 예전 크기의 세계를 시험할 때만 따로 준다.
    static func newCareer(setup: CareerSetup, now: Date, seed: UInt64, leagueSize: Int) -> Game {
        var game = Game(funds: FundsLedger(startedAt: now), rng: SeededRNG(seed: seed), chargeAnchor: now)
        let sport = setup.sport
        if sport != .baseball { game.sportChoice = sport }
        var taken: Set<String> = []
        for tier in LeagueTier.allCases {
            for slot in 0..<leagueSize {
                let id = game.teams.count
                let identity = game.newTeamIdentity(tier: tier, slot: slot, taken: taken)
                taken.insert(identity.name)
                game.teams.append(Team(
                    id: id, name: identity.name, city: identity.city, tier: tier, isUser: false, season: 1))
                game.setUpCPUTeam(id, slot: slot)
            }
        }
        let sixth = game.teams(in: .citizenAmateur)
        let club = sixth[sixth.count / 2].id
        game.userTeamID = club
        game.createCareerPlayer(setup, team: club)
        game.startSeasonSchedules()
        game.careerStartSeason()
        game.post("\(setup.name), \(game.teams[club].name)에 입단! \(LeagueTier.citizenAmateur.displayName) 리그에서 커리어를 시작합니다.")
        game.postCareerTalent()
        return game
    }

    /// 내 선수를 만들어 구단에 넣는다.
    /// 시작 능력과 잠재력은 타고난 재능이라 선수마다 다르고, 그 위에 직접 고른 시작 포인트가 더해진다.
    mutating func createCareerPlayer(_ setup: CareerSetup, team: TeamID) {
        let tier = teams[team].tier
        var spec = PlayerFactory.Spec(position: setup.position, tier: tier, season: season)
        spec.ability = Balance.careerStartAbility
        spec.age = Balance.careerStartAge...Balance.careerStartAge
        spec.potential = Balance.careerPotential
        spec.scoutBias = 0
        var player = makePlayer(spec)
        player.name = setup.name
        player.bats = setup.bats
        player.throwsHand = setup.throwsHand
        player.origin = "\(setup.hometown) 출신 유망주"
        player.traits = []
        let talent = player.ability
        for (key, count) in setup.validPoints {
            player.attributes[key] = min(99, player.attributes[key] + Double(count) * Balance.careerStartPointValue)
        }
        player.potential = max(player.potential, player.ability)
        player.abilityAtSeasonStart = player.ability
        player.contract = Contract(salary: Balance.marketSalary(ability: player.ability), seasonsLeft: 2)
        players[player.id] = player

        career = Career(playerID: player.id, season: season)
        career?.peakAbility = player.ability
        career?.startAbility = talent
        joinCareerClub(team)
    }

    /// 입단할 때 스카우트가 본 재능을 소식으로 알린다.
    mutating func postCareerTalent() {
        guard let me = myPlayer, let talent = careerTalent else { return }
        let born = career?.startAbility ?? me.ability
        post("스카우트 평가: \(me.name)의 재능은 \"\(talent.rawValue)\". \(talent.note) (타고난 능력 \(Int(born)))")
    }

    /// 내 선수가 구단에 들어간다. 같은 포지션에서 가장 약한 선수의 자리를 넘겨받아 로스터 구성이 그대로 유지된다.
    mutating func joinCareerClub(_ team: TeamID) {
        guard let career, let me = players[career.playerID] else { return }
        if let old = me.teamID { clearCareerLineup(old) }
        let peers = roster(of: team).filter { $0.position == me.position && $0.id != me.id }
        if let weakest = peers.min(by: { ($0.ability, $0.id) < ($1.ability, $1.id) }) {
            moveToFreeAgency(weakest.id)
        }
        add(me.id, to: team)
        // 등판 간격은 구단마다 따로 세는 경기 수로 잰다. 옮긴 구단에서는 바로 나올 수 있게 한다.
        players[me.id]?.lastStartGame = -99
        userTeamID = team
        if self.career?.clubs.last != teams[team].name { self.career?.clubs.append(teams[team].name) }
        self.career?.matchesAtClub = 0
        refreshCareerRival()
        if teams[team].tier < career.bestTier { self.career?.bestTier = teams[team].tier }
    }

    /// 내 선수 때문에 정해 둔 출전 지시를 지운다.
    mutating func clearCareerLineup(_ team: TeamID) {
        guard let career else { return }
        teams[team].lineupOverride = []
        teams[team].firstReliever = nil
        if teams[team].starterOverride == career.playerID { teams[team].starterOverride = nil }
        teams[team].policy = PitchingPolicy()
    }

    // MARK: 출전

    /// 감독이 내 선발 투수를 얼마나 오래 맡기는지. 신뢰가 높을수록 길게 던진다.
    static func careerPolicy(trust: Double) -> PitchingPolicy {
        var policy = PitchingPolicy()
        policy.starterPitchLimit = Int(70 + trust * 0.4)
        policy.starterRunLimit = trust >= 70 ? 6 : trust >= 35 ? 5 : 4
        return policy
    }

    // MARK: 출전 (축구)

    /// 축구: 감독이 나를 선발로 쓸지. 같은 포지션 선수들과 능력을 비교하고, 감독 신뢰만큼 보정한다 (−5 ~ +5).
    /// 골키퍼는 교체로 나올 수 없어서, 주전이 아니어도 친선 경기와 네 경기 중 한 경기에는 선발로 나온다.
    func careerFootballStarts(kind: MatchKind) -> Bool {
        guard let career, let me = players[career.playerID], let teamID = me.teamID else { return false }
        // 출장 정지 중에는 리그 경기에 나서지 못한다.
        if kind != .friendly, (me.suspendedMatches ?? 0) > 0 { return false }
        let team = teams[teamID]
        let quota = formation(of: teamID).slots.filter { $0 == me.position }.count
        let peers = roster(of: teamID).filter { $0.position == me.position && $0.id != me.id }
            .map(\.ability).sorted(by: >)
        if peers.count < quota { return true }
        if quota > 0, me.ability + (career.trust - 50) / 10 >= peers[quota - 1] { return true }
        if me.position == .goalkeeper {
            return kind == .friendly || team.gamesPlayed % Balance.careerKeeperRotation == 0
        }
        return false
    }

    /// 다음 경기에 내 축구 선수가 어떻게 나오는지 (화면 안내용).
    public var careerFootballPlan: (starts: Bool, subMinute: Int?)? {
        guard let career, let me = players[career.playerID], me.position.sport == .football,
              let next = nextMatch()
        else { return nil }
        let starts = careerFootballStarts(kind: next.kind)
        return (starts, starts || me.position == .goalkeeper ? nil : Balance.careerSubMinute(trust: career.trust))
    }

    /// 축구: 선발 11명을 정한다. 내가 선발이면 같은 포지션에서 가장 약한 선발 대신 들어가고,
    /// 아니면 벤치에서 시작해 정해진 시간에 교체로 들어간다.
    mutating func prepareCareerFootballLineup(kind: MatchKind) {
        guard let career, let me = players[career.playerID] else { return }
        let starts = careerFootballStarts(kind: kind)
        var team = teams[userTeamID]
        team.lineupOverride = []
        team.formation = formation(of: userTeamID)
        self.career?.subMinute = nil
        guard let auto = FootballLineupBuilder.build(
            team: team, players: players, ignoreSuspensions: kind == .friendly)
        else { return }
        var ids = auto.starters.map(\.id)
        if starts, !ids.contains(me.id) {
            let same = ids.indices.filter { players[ids[$0]]?.position == me.position }
            let candidates = same.isEmpty ? ids.indices.filter { players[ids[$0]]?.position != .goalkeeper } : same
            if let index = candidates.min(by: {
                (players[ids[$0]]?.ability ?? 0, $0) < (players[ids[$1]]?.ability ?? 0, $1)
            }) {
                ids[index] = me.id
            }
        } else if !starts, let index = ids.firstIndex(of: me.id) {
            let bench = auto.bench.compactMap { players[$0] }
            if let replacement = bench.first(where: { $0.position == me.position }) {
                ids[index] = replacement.id
            }
        }
        teams[userTeamID].lineupOverride = ids == auto.starters.map(\.id) ? [] : ids
        let banned = kind != .friendly && (me.suspendedMatches ?? 0) > 0
        if !ids.contains(me.id), me.position != .goalkeeper, !banned {
            self.career?.subMinute = Balance.careerSubMinute(trust: career.trust)
        }
    }

    /// 축구: 경기 엔진에 넘어간 내 선수에게 세부 기록, 플레이 스타일, 교체 투입 시간을 붙인다.
    func decorateCareerFootball(_ match: inout FootballMatch, userIsHome: Bool) {
        guard let career else { return }
        var side = userIsHome ? match.home : match.away
        guard let index = side.players.firstIndex(where: { $0.playerID == career.playerID }) else { return }
        side.players[index].detail = FootballDetail()
        let style = career.style ?? .balanced
        if style != .balanced, side.players[index].natural != .goalkeeper { side.players[index].style = style }
        if !side.players[index].isOnPitch, let minute = career.subMinute {
            side.guaranteedSub = career.playerID
            side.guaranteedMinute = minute
        }
        if userIsHome { match.home = side } else { match.away = side }
    }

    /// 축구: 경기 전에 플레이 스타일을 고른다.
    public mutating func setCareerStyle(_ style: PlayStyle) {
        guard career != nil else { return }
        career?.style = style == .balanced ? nil : style
    }

    /// 다음 경기에 내 선발 투수가 나오는 차례인지.
    public var careerStartsNextMatch: Bool {
        guard let me = myPlayer, me.position == .starter, let team = me.teamID else { return false }
        return teams[team].gamesPlayed - me.lastStartGame > Balance.starterRest(teams[team].tier)
    }

    /// 경기 전에 내 선수의 출전을 정한다.
    /// - 타자: 매 경기 선발로 나온다. 타순은 타격 순이고, 감독 신뢰가 높으면 앞으로 당겨진다.
    /// - 선발 투수: 쉬는 날을 채우면 반드시 선발로 나온다.
    /// - 불펜 투수: 선발이 내려가면 가장 먼저 올라온다.
    mutating func prepareCareerLineup(kind: MatchKind = .regular) {
        guard let career, let me = players[career.playerID], me.teamID == userTeamID else { return }
        if me.position.sport == .football {
            prepareCareerFootballLineup(kind: kind)
            return
        }
        if me.position.sport == .basketball {
            prepareCareerBasketballLineup()
            return
        }
        var team = teams[userTeamID]
        team.lineupOverride = []
        team.firstReliever = nil
        team.policy = PitchingPolicy()
        if team.starterOverride == me.id { team.starterOverride = nil }

        if me.position == .starter {
            if team.gamesPlayed - me.lastStartGame > Balance.starterRest(team.tier) {
                team.starterOverride = me.id
                team.policy = Self.careerPolicy(trust: career.trust)
            }
        } else if me.isPitcher {
            team.firstReliever = me.id
        } else if let lineup = LineupBuilder.build(team: team, players: players) {
            var ids = lineup.batters.map(\.id)
            if !ids.contains(me.id) {
                // 같은 포지션 선수의 자리에 들어가고, 없으면 타격이 가장 약한 선수 대신 나온다.
                let index = ids.lastIndex { players[$0]?.position == me.position } ?? ids.count - 1
                ids[index] = me.id
            }
            let shift = (career.trust - 50) * 0.3
            func value(_ id: PlayerID) -> Double {
                guard let player = players[id] else { return 0 }
                return LineupBuilder.battingValue(player) + (id == me.id ? shift : 0)
            }
            ids.sort { (value($0), -$0) > (value($1), -$1) }
            team.lineupOverride = ids
        }
        teams[userTeamID] = team
    }

    // MARK: 화면에 보일 기록

    /// 통산 기록: 끝난 시즌들에 진행 중인 시즌을 더한 값.
    public var careerTotals: (batting: BattingLine, pitching: PitchingLine, ratedGames: Int, ratingTotal: Double) {
        var batting = BattingLine()
        var pitching = PitchingLine()
        var games = 0
        var total = 0.0
        guard let career else { return (batting, pitching, games, total) }
        for season in career.history {
            batting += season.batting
            pitching += season.pitching
            games += season.ratedGames
            total += season.ratingTotal
        }
        if !career.seasonClosed, let me = players[career.playerID] {
            batting += me.batting
            pitching += me.pitching
            games += career.seasonRatedGames
            total += career.seasonRatingTotal
        }
        return (batting, pitching, games, total)
    }

    /// 축구 선수의 통산 기록: 끝난 시즌들에 진행 중인 시즌을 더한 값.
    public var careerFootballTotals: FootballLine {
        var line = FootballLine()
        guard let career else { return line }
        for season in career.history { line += season.football ?? FootballLine() }
        if !career.seasonClosed, let me = players[career.playerID] { line += me.football ?? FootballLine() }
        return line
    }
}
