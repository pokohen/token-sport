import Foundation

/// 게임 전체 상태. 이것 하나를 저장하면 그대로 이어서 할 수 있다.
public struct Game: Codable, Equatable, Sendable {
    public var settings = Settings()
    public var funds: FundsLedger
    /// 종목. 종목을 나누기 전의 저장 파일에는 없고, 없으면 야구다.
    public internal(set) var sportChoice: Sport?

    // 세계
    var rng: SeededRNG
    public internal(set) var season = 1
    /// 이번 정규시즌에서 끝난 라운드 수 (0~36).
    public internal(set) var round = 0
    public internal(set) var phase = SeasonPhase.regular
    public internal(set) var friendliesPlayed = 0
    public internal(set) var players: [PlayerID: Player] = [:]
    var nextPlayerID = 1
    public internal(set) var teams: [Team] = []
    public internal(set) var userTeamID: TeamID = 0
    /// [리그][라운드][경기]
    public internal(set) var schedules: [[[Fixture]]] = []
    /// [리그] 순위표 줄 (정렬 전)
    public internal(set) var standings: [[StandingRow]] = []
    public internal(set) var freeAgents: [PlayerID] = []
    /// 시즌을 시작할 때의 리그별 CPU 팀 평균 강도 (맞춰주기 한도 계산용).
    var leagueStartAverage: [Double] = []
    public internal(set) var news: [NewsItem] = []
    var nextNewsID = 1

    // 경기
    public internal(set) var charges = 1
    public internal(set) var chargeAnchor: Date
    public internal(set) var live: LiveMatch?
    /// 진행 중인 축구 경기. 야구는 `live`를 쓴다.
    public internal(set) var liveFootball: LiveFootballMatch?
    /// 진행 중인 농구 경기. (예전 저장 파일에는 없다.)
    public internal(set) var liveBasketball: LiveBasketballMatch?
    public internal(set) var lastResult: LastResult?
    /// 이번 틱에 뛴 선수의 출전 계수.
    var playedFactor: [PlayerID: Double] = [:]

    // 승강
    public internal(set) var appliedForPromotion = false
    public internal(set) var series: [PlayoffSeries] = []
    var pendingMoves: [TierMove] = []
    /// 지난 시즌 승률 (드래프트 순서용).
    var lastWinRate: [TeamID: Double] = [:]
    public internal(set) var awards: [AwardRecord] = []
    public internal(set) var bestTier = LeagueTier.citizenAmateur
    public internal(set) var relegatedThisOffseason = false

    // 구단
    public internal(set) var promotionUses: [String: Int] = [:]
    /// 재정 위기: 남은 유예 경기 수. 위기가 아니면 nil.
    public internal(set) var crisisMatchesLeft: Int?
    public internal(set) var isBankrupt = false
    /// 강등 뒤 스폰서 수입이 줄어드는 남은 시즌 수.
    public internal(set) var sponsorPenaltySeasons = 0
    public internal(set) var hallOfFame: [HallEntry] = []
    /// 유소년 야구 교실: 다음 입단 테스트에 후보가 더 온다.
    var youthBoost = 0

    // 이적 시장
    public internal(set) var offers: [TransferOffer] = []
    public internal(set) var proposals: [Proposal] = []
    public internal(set) var counters: [Proposal] = []
    public internal(set) var candidates: [Candidate] = []
    public internal(set) var scoutTrip: ScoutTrip?
    var nextMarketID = 1
    var draftDone = false
    var expiryNoticeSent = false

    /// 마지막으로 경기 기회가 저절로 생긴 뒤에 토큰으로 산 경기 수 (살수록 비싸진다). 예전 저장 파일에는 없다.
    public internal(set) var extraMatchesBought: Int?
    /// 토큰으로 산 경기 기회를 아직 쓰지 않았는지. 선수 모드에서는 그 경기에서 실전 경험을 얻는다.
    public internal(set) var extraMatchPending: Bool?
    /// 이번 시즌 컵대회 (선수 모드에서만 열린다. 예전 저장 파일에는 없다).
    public internal(set) var cup: Cup?

    // 선수 모드. 구단 모드와 예전 저장 파일에는 없다.
    public internal(set) var career: Career?
    /// 은퇴한 내 선수들의 명예의 전당.
    public internal(set) var careerHall: [CareerRecord]?

    // MARK: 읽기

    public var sport: Sport { sportChoice ?? .baseball }
    /// 이번 시즌의 정규시즌 라운드 수. 지금 쓰는 일정에서 읽으므로, 예전 크기의 리그로 시작한 시즌도 끝까지 맞는다.
    public var roundsPerSeason: Int { schedules.first?.count ?? Balance.roundsPerSeason(sport) }
    /// 내 경기가 진행 중인지 (종목과 상관없이).
    public var isMatchLive: Bool { live != nil || liveFootball != nil || liveBasketball != nil }

    public func rosterLimit(_ tier: LeagueTier) -> Int { Balance.rosterLimit(tier, sport: sport) }
    func rosterPositions(_ tier: LeagueTier) -> [Position] { PlayerFactory.rosterPositions(tier, sport: sport) }

    /// 이 구단이 지금 경기를 치를 수 있는 구성인지.
    public func canField(_ team: Team) -> Bool {
        switch sport {
        case .football: FootballLineupBuilder.build(team: team, players: players) != nil
        case .basketball: BasketballLineupBuilder.build(team: team, players: players) != nil
        case .baseball: LineupBuilder.build(team: team, players: players) != nil
        }
    }

    public var userTeam: Team { teams[userTeamID] }
    public var userTier: LeagueTier { teams[userTeamID].tier }

    public func teams(in tier: LeagueTier) -> [Team] {
        teams.filter { $0.tier == tier }
    }

    public func rankedStandings(_ tier: LeagueTier) -> [StandingRow] {
        Standings.ranked(standings[tier.index], sport: sport)
    }

    public func rank(of team: TeamID) -> Int {
        let rows = rankedStandings(teams[team].tier)
        return (rows.firstIndex { $0.teamID == team } ?? 0) + 1
    }

    public func roster(of team: TeamID) -> [Player] {
        teams[team].roster.compactMap { players[$0] }
    }

    public func strength(of team: TeamID) -> Double {
        switch sport {
        case .football: FootballLineupBuilder.strength(team: teams[team], players: players)
        case .basketball: BasketballLineupBuilder.strength(team: teams[team], players: players)
        case .baseball: LineupBuilder.strength(team: teams[team], players: players)
        }
    }

    /// 가격 난이도를 곱한 비용.
    public func price(_ base: Int) -> Int {
        max(0, Int((Double(base) * settings.priceDifficulty).rounded()))
    }

    /// 경기마다 내는 연봉 합계.
    public var salaryPerMatch: Int {
        let season = roster(of: userTeamID).reduce(0) { $0 + $1.contract.salary }
        return price(season / roundsPerSeason)
    }

    /// 계약이 끝나 떠날 선수인지 (재계약하지 않으면).
    public func isExpiring(_ player: Player) -> Bool {
        phase == .offseason ? player.contract.seasonsLeft <= 0 : player.contract.seasonsLeft <= 1
    }

    /// 이적 기간. 야구는 오프시즌과 시즌 중 트레이드 마감 전, 축구는 여름과 겨울 두 번이다.
    public var tradeWindowOpen: Bool {
        if phase == .offseason { return true }
        guard phase == .regular else { return false }
        if sport == .football {
            return round < Balance.footballSummerWindowRounds || Balance.footballWinterWindow.contains(round)
        }
        return round < Balance.tradeDeadlineRound
    }

    // MARK: 소식

    mutating func post(_ text: String) {
        news.append(NewsItem(id: nextNewsID, season: season, text: text))
        nextNewsID += 1
        if news.count > 60 { news.removeFirst(news.count - 60) }
    }

    // MARK: 경기 기회

    /// 1시간마다 1개씩, 최대 3개까지 쌓인다.
    public mutating func refreshCharges(now: Date) {
        if charges >= Balance.maxMatchCharges {
            chargeAnchor = now
            return
        }
        while charges < Balance.maxMatchCharges,
              now.timeIntervalSince(chargeAnchor) >= Balance.matchChargeInterval {
            charges += 1
            // 기회가 저절로 생기면 추가 경기 값이 처음으로 돌아간다.
            extraMatchesBought = nil
            chargeAnchor = chargeAnchor.addingTimeInterval(Balance.matchChargeInterval)
        }
        if charges >= Balance.maxMatchCharges { chargeAnchor = now }
        if chargeAnchor > now { chargeAnchor = now }
    }

    /// 다음 경기 기회까지 남은 시간. 이미 가득 찼으면 nil.
    public func timeToNextCharge(now: Date) -> TimeInterval? {
        guard charges < Balance.maxMatchCharges else { return nil }
        return max(0, Balance.matchChargeInterval - now.timeIntervalSince(chargeAnchor))
    }

    // MARK: 추가 경기

    /// 지금 토큰(구단 자금 또는 훈련 포인트)으로 경기 기회를 하나 사는 값.
    /// 연달아 살수록 두 배씩 비싸지고, 경기 기회가 저절로 하나 생기면 처음 값으로 돌아간다.
    public var extraMatchCost: Int {
        price(Balance.extraMatchCost << min(extraMatchesBought ?? 0, Balance.extraMatchMaxDoublings))
    }

    /// 지금 추가 경기를 살 수 없는 이유. 살 수 있으면 nil.
    public var extraMatchBlockedReason: String? {
        if isBankrupt { return "구단이 해체되었습니다." }
        if isMatchLive { return "진행 중인 경기가 끝나야 합니다." }
        if charges > 0 { return "경기 기회가 남아 있습니다." }
        if nextMatch() == nil { return "지금은 치를 경기가 없습니다." }
        return insufficientFundsReason(extraMatchCost)
    }

    /// 한 시간을 기다리지 않고 토큰으로 경기 기회를 하나 산다. 경기 기회가 없을 때만 살 수 있다.
    public mutating func buyExtraMatch(now: Date) throws {
        refreshCharges(now: now)
        if let reason = extraMatchBlockedReason { throw GameError(reason) }
        funds.spend(extraMatchCost, .extraMatch)
        extraMatchesBought = (extraMatchesBought ?? 0) + 1
        if isCareer { extraMatchPending = true }
        charges += 1
    }

    // MARK: 결과 바로 보기

    /// 진행 중인 경기를 곧바로 끝내는 값.
    public var skipMatchCost: Int { price(Balance.skipMatchCost) }

    /// 지금 결과 바로 보기를 할 수 없는 이유. 할 수 있으면 nil.
    public var skipMatchBlockedReason: String? {
        if !isMatchLive { return "진행 중인 경기가 없습니다." }
        return insufficientFundsReason(skipMatchCost)
    }

    /// 토큰을 내고 남은 경기를 화면 없이 끝까지 치른다.
    /// 경기는 시작할 때 정해진 시드로 흘러가므로, 지켜봤을 때와 결과가 같다.
    public mutating func skipMatchToEnd() throws {
        if let reason = skipMatchBlockedReason { throw GameError(reason) }
        funds.spend(skipMatchCost, .skipMatch)
        runMatchToEnd()
    }

    // MARK: 선수 만들기

    mutating func makePlayer(_ spec: PlayerFactory.Spec) -> Player {
        let player = PlayerFactory.make(id: nextPlayerID, spec: spec, &rng)
        nextPlayerID += 1
        players[player.id] = player
        return player
    }

    mutating func add(_ playerID: PlayerID, to team: TeamID) {
        guard var player = players[playerID] else { return }
        if let old = player.teamID { teams[old].roster.removeAll { $0 == playerID } }
        freeAgents.removeAll { $0 == playerID }
        player.teamID = team
        player.joinedSeason = season
        player.joinedTier = teams[team].tier.rawValue
        player.isFranchiseStar = false
        // 구단을 옮긴 선수는 적어도 이번 시즌은 뛴다. (계약이 끝난 채로 팔려 간 선수가
        // 시즌 중에 트레이드로 돌아왔다가 곧바로 떠나는 일이 없게 한다.)
        player.contract.seasonsLeft = max(1, player.contract.seasonsLeft)
        players[playerID] = player
        teams[team].roster.append(playerID)
    }

    mutating func moveToFreeAgency(_ playerID: PlayerID) {
        guard var player = players[playerID] else { return }
        if let old = player.teamID {
            teams[old].roster.removeAll { $0 == playerID }
            teams[old].lineupOverride.removeAll { $0 == playerID }
            if teams[old].starterOverride == playerID { teams[old].starterOverride = nil }
        }
        player.teamID = nil
        player.contract.seasonsLeft = 0
        players[playerID] = player
        if !freeAgents.contains(playerID) { freeAgents.append(playerID) }
    }

    mutating func removePlayer(_ playerID: PlayerID) {
        if let team = players[playerID]?.teamID {
            teams[team].roster.removeAll { $0 == playerID }
            teams[team].lineupOverride.removeAll { $0 == playerID }
            if teams[team].starterOverride == playerID { teams[team].starterOverride = nil }
        }
        freeAgents.removeAll { $0 == playerID }
        players[playerID] = nil
    }
}
