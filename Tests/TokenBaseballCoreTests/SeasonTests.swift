import Foundation
import Testing
@testable import TokenBaseballCore

/// 테스트용 자동 감독: 사람이 누를 만한 것을 대신 누른다.
struct AutoManager {
    var clock = TestGame.start
    var tokenID = 0
    /// 경기마다 쓰는 토큰.
    var tokensPerMatch: Int
    var log: [String] = []

    mutating func playOne(_ game: inout Game) throws {
        clock = clock.addingTimeInterval(3600)
        tokenID += 1
        if tokensPerMatch > 0 {
            TestGame.addTokens(&game, tokensPerMatch, id: "t\(tokenID)", at: clock)
        }
        manage(&game)
        try game.startMatch(now: clock)
        game.runMatchToEnd()
    }

    mutating func manage(_ game: inout Game) {
        guard !game.isBankrupt else { return }
        // 승격 신청: 인지도가 모자라면 홍보로 채운다.
        if game.phase == .regular, !game.appliedForPromotion, let need = game.promotionRequirement,
           game.round < Balance.applicationDeadlineRound {
            for promotion in [Promotion.tv, .festival, .sns, .newspaper, .flyer] where game.userTeam.fame < need.fame {
                for _ in 0..<4 where game.userTeam.fame < need.fame { try? game.promote(promotion) }
            }
            try? game.applyForPromotion()
        }
        // 시설
        for facility in Facility.allCases {
            if let cost = game.upgradeCost(facility), game.funds.balance > cost * 3 { try? game.upgrade(facility) }
        }
        // 재계약: 요구 조건을 그대로 들어준다.
        for player in game.roster(of: game.userTeamID) where game.isExpiring(player) {
            let demand = game.renewalDemand(player)
            try? game.proposeRenewal(player.id, salary: demand.salary, years: demand.years)
        }
        for counter in game.counters { try? game.acceptCounter(counter.id) }
        // 영입: 테스트를 열고, 지금 선수보다 낫거나 크게 클 후보와 계약한다. 자리가 없으면 가장 약한 선수를 내보낸다.
        if game.candidates.isEmpty { try? game.holdTryout() }
        for candidate in game.candidates {
            guard let player = game.players[candidate.playerID] else { continue }
            let mates = game.roster(of: game.userTeamID).filter { $0.isPitcher == player.isPitcher }
            guard let worst = mates.min(by: { ($0.ability, $0.id) < ($1.ability, $1.id) }) else { continue }
            let promising = player.age <= 23 && player.potential > worst.ability + 12
            guard player.ability > worst.ability + 2 || promising || candidate.source == .draft else { continue }
            if game.userTeam.roster.count >= Balance.rosterLimit(game.userTier, sport: .baseball) { try? game.release(worst.id) }
            try? game.sign(candidate: candidate.id)
        }
        // 오프시즌에는 FA 시장에서 가장 좋은 선수에게 제안한다.
        if game.phase == .offseason, game.userTeam.roster.count < Balance.rosterLimit(game.userTier, sport: .baseball) {
            for player in game.freeAgentMarket.prefix(3) {
                try? game.proposeFreeAgent(
                    player.id, salary: Balance.marketSalary(ability: player.ability) * 3 / 2, years: 2)
            }
        }
        if game.userTeam.scoutLevel >= 1, game.scoutTrip == nil { try? game.sendScout(.national) }
        // 들어온 오퍼는 거절한다.
        for offer in game.offers { try? game.respond(to: offer.id, .reject) }
    }
}

enum Invariants {
    static func check(_ game: Game, _ comment: Comment) {
        let size = Balance.teamsPerLeague(game.sport)
        #expect(game.teams.count == size * 6, comment)
        var seen: Set<PlayerID> = []
        for tier in LeagueTier.allCases {
            let teams = game.teams(in: tier)
            #expect(teams.count == size, "\(comment) \(tier.displayName)")
            for team in teams {
                let roster = game.roster(of: team.id)
                #expect(roster.count == team.roster.count, "\(comment) 없는 선수가 로스터에 있음")
                #expect(roster.count <= game.rosterLimit(tier), "\(comment) \(team.name) \(roster.count)명")
                if game.sport == .football {
                    #expect(roster.allSatisfy { $0.position.sport == .football }, "\(comment) \(team.name) 야구 선수")
                    #expect(roster.contains { $0.position == .goalkeeper }, "\(comment) \(team.name) 골키퍼 없음")
                    #expect(roster.count >= 11, "\(comment) \(team.name) \(roster.count)명")
                } else {
                    #expect(roster.allSatisfy { $0.position.sport == .baseball }, "\(comment) \(team.name) 축구 선수")
                    #expect(roster.filter { !$0.isPitcher }.count >= 9, "\(comment) \(team.name) 야수 부족")
                    #expect(roster.filter { $0.isPitcher }.count >= 2, "\(comment) \(team.name) 투수 부족")
                }
                #expect(game.canField(team), "\(comment) \(team.name)")
                for player in roster {
                    #expect(player.teamID == team.id, comment)
                    #expect(player.ability <= player.potential + 0.01, "\(comment) \(player.name)")
                    #expect(seen.insert(player.id).inserted, "\(comment) 두 팀에 있는 선수")
                    for key in Attributes.Key.allCases {
                        #expect((1.0...99.0).contains(player.attributes[key]), comment)
                    }
                }
                if !team.isUser {
                    let strength = game.strength(of: team.id)
                    let range = Balance.strengthRange(tier)
                    #expect(
                        strength >= range.lowerBound - 0.01 && strength <= range.upperBound + 0.01,
                        "\(comment) \(team.name) 강도 \(strength)")
                }
            }
        }
        for id in game.freeAgents {
            #expect(game.players[id]?.teamID == nil, comment)
            #expect(!seen.contains(id), comment)
        }
    }
}

@Suite struct SeasonFlowTests {
    @Test func 한_시즌이_36라운드로_끝나고_오프시즌을_거쳐_다음_시즌이_시작된다() throws {
        var game = TestGame.make(seed: 11)
        var manager = AutoManager(tokensPerMatch: 300_000)
        for _ in 0..<36 {
            #expect(game.phase == .regular)
            try manager.playOne(&game)
        }
        // 정규시즌이 끝나면 (플레이오프가 없으면) 오프시즌이다.
        #expect(game.round == 36)
        #expect(game.phase != .regular)
        #expect(!game.awards.isEmpty)
        for tier in LeagueTier.allCases {
            #expect(game.awards.contains { $0.tier == tier && $0.title == "MVP" && $0.season == 1 })
        }

        while game.phase == .playoff { try manager.playOne(&game) }
        #expect(game.phase == .offseason)
        #expect(game.nextMatch()?.kind == .friendly)
        // 친선 상대는 다른 리그 팀이다.
        #expect(game.teams[try #require(game.nextMatch()).opponent].tier != game.userTier)

        let standingsBefore = game.standings
        for played in 1...5 {
            try manager.playOne(&game)
            if played < 5 {
                #expect(game.friendliesPlayed == played)
                // 친선 경기는 순위에 반영되지 않는다.
                #expect(game.standings == standingsBefore)
            }
        }
        #expect(game.phase == .regular)
        #expect(game.season == 2)
        #expect(game.round == 0)
        #expect(game.standings.flatMap { $0 }.allSatisfy { $0.games == 0 })
        Invariants.check(game, "2시즌 시작")
    }

    @Test func 신청하지_않으면_1위를_해도_승격하지_못하고_다음_순위_팀이_올라간다() throws {
        var game = TestGame.make(seed: 21)
        TestGame.addTokens(&game, 500_000_000, id: "seed", at: TestGame.start)
        // 내 팀을 압도적으로 강하게 만든다.
        for id in game.userTeam.roster {
            for key in Attributes.Key.allCases { game.players[id]?.attributes[key] = 60 }
            game.players[id]?.potential = 60
        }
        var manager = AutoManager(tokensPerMatch: 0)
        for _ in 0..<36 {
            manager.clock = manager.clock.addingTimeInterval(3600)
            try game.startMatch(now: manager.clock)
            game.runMatchToEnd()
        }
        #expect(game.lastWinRate[game.userTeamID] ?? 0 > 0.8)
        #expect(game.phase == .offseason)
        #expect(game.userTier == .citizenAmateur)
        // 6부에서 두 팀은 올라갔거나 플레이오프를 치렀고, 리그는 여전히 10팀이다.
        #expect(game.teams(in: .citizenAmateur).count == 10)
        #expect(game.teams(in: .citizenSemiPro).count == 10)
        #expect(game.news.contains { $0.text.contains("신청하지 않아") })
    }

    @Test func 신청하고_1위를_하면_자동_승격한다() throws {
        var game = TestGame.make(seed: 22)
        for id in game.userTeam.roster {
            for key in Attributes.Key.allCases { game.players[id]?.attributes[key] = 60 }
            game.players[id]?.potential = 60
        }
        var manager = AutoManager(tokensPerMatch: 3_000_000)
        for _ in 0..<36 { try manager.playOne(&game) }

        #expect(game.appliedForPromotion || game.season > 1 || game.phase == .offseason)
        #expect(game.phase == .offseason)
        #expect(game.userTier == .citizenSemiPro)
        #expect(game.bestTier == .citizenSemiPro)
        #expect(game.news.contains { $0.text.hasPrefix("승격!") })
        #expect(game.funds.seasonIncome["상금·지원금"] ?? 0 > 0)
        for tier in LeagueTier.allCases { #expect(game.teams(in: tier).count == 10) }
    }

    @Test func 꼴찌는_자동_강등되고_9위는_승강_플레이오프를_치른다() throws {
        var game = TestGame.make(seed: 23)
        TestGame.addTokens(&game, 500_000_000, id: "seed", at: TestGame.start)
        // 내 팀을 5부로 올려 놓고 아주 약하게 만든다.
        let swap = game.teams(in: .citizenSemiPro)[0].id
        game.teams[swap].tier = .citizenAmateur
        game.teams[game.userTeamID].tier = .citizenSemiPro
        game.startSeasonSchedules()
        for id in game.userTeam.roster {
            for key in Attributes.Key.allCases { game.players[id]?.attributes[key] = 5 }
        }
        var manager = AutoManager(tokensPerMatch: 0)
        for _ in 0..<36 {
            manager.clock = manager.clock.addingTimeInterval(3600)
            try game.startMatch(now: manager.clock)
            game.runMatchToEnd()
        }
        #expect(game.phase == .offseason)
        #expect(game.userTier == .citizenAmateur)
        #expect(game.relegatedThisOffseason)
        #expect(game.sponsorPenaltySeasons == 1)
        #expect(game.news.contains { $0.text.hasPrefix("강등") })
        // 강등되면 오퍼가 몰려온다.
        #expect(game.offers.count >= 3)
    }

    @Test func 이위는_와일드카드를_거쳐_3전_2선승_승강_플레이오프를_치르고_이기면_올라간다() throws {
        var game = TestGame.make(seed: 24)
        for id in game.userTeam.roster {
            for key in Attributes.Key.allCases { game.players[id]?.attributes[key] = 55 }
            game.players[id]?.potential = 55
        }
        // 정규시즌 마지막 직전까지 순위표를 직접 채운다: 내 팀이 2위.
        let tier = LeagueTier.citizenAmateur
        game.round = 36
        game.appliedForPromotion = true
        for index in game.standings[tier.index].indices {
            let id = game.standings[tier.index][index].teamID
            game.standings[tier.index][index].wins = id == game.userTeamID ? 30 : 10 + index
            game.standings[tier.index][index].losses = 36 - game.standings[tier.index][index].wins
        }
        let top = game.standings[tier.index].firstIndex { $0.teamID != game.userTeamID }!
        game.standings[tier.index][top].wins = 34
        game.standings[tier.index][top].losses = 2
        for other in LeagueTier.allCases where other != tier {
            for index in game.standings[other.index].indices {
                game.standings[other.index][index].wins = 20 - index
                game.standings[other.index][index].losses = 16 + index
            }
        }
        game.endRegularSeason()

        #expect(game.phase == .playoff)
        // 먼저 3위와 승격 와일드카드: 2위인 내 구단의 홈이고, 한 번만 이기면 된다.
        let wildcard = try #require(game.series.first { $0.involves(game.userTeamID) })
        #expect(wildcard.kind == .wildcard)
        #expect(wildcard.upperTeam == game.userTeamID)
        #expect(wildcard.upperTier == .citizenSemiPro)
        #expect(game.nextMatch()?.kind == .playoff)
        #expect(game.nextMatch()?.userIsHome == true)
        #expect(game.nextMatch()?.label == "승격 와일드카드 1차전")

        var clock = TestGame.start
        var games = 0
        var sawPromotionSeries = false
        while game.phase == .playoff {
            clock = clock.addingTimeInterval(3600)
            if let mine = game.series.first(where: { $0.involves(game.userTeamID) }), mine.kind == .bestOfThree {
                // 승강 플레이오프: 윗 리그 9위가 1·3차전 홈.
                sawPromotionSeries = true
                #expect(mine.lowerTeam == game.userTeamID)
                #expect(game.nextMatch()?.userIsHome == (mine.played == 1))
            }
            try game.startMatch(now: clock)
            #expect(game.live?.state.rules.maxInnings == nil)
            game.runMatchToEnd()
            games += 1
        }
        #expect(sawPromotionSeries)
        #expect((3...5).contains(games))
        #expect(game.phase == .offseason)
        let promoted = game.news.contains { $0.text.hasPrefix("승격!") }
        #expect(game.userTier == (promoted ? .citizenSemiPro : .citizenAmateur))
        for league in LeagueTier.allCases { #expect(game.teams(in: league).count == 10) }
    }
}

@Suite struct ContractTests {
    static func toOffseason(_ game: inout Game, _ manager: inout AutoManager) throws {
        while game.phase != .offseason { try manager.playOne(&game) }
    }

    @Test func 재계약하지_않은_선수는_오프시즌이_끝나면_떠난다() throws {
        var game = TestGame.make(seed: 31)
        TestGame.addTokens(&game, 500_000_000, id: "seed", at: TestGame.start)
        // 모든 선수의 계약을 이번 시즌까지로 만든다.
        for id in game.userTeam.roster { game.players[id]?.contract.seasonsLeft = 1 }
        let original = game.userTeam.roster
        // 은퇴하지 않을 젊은 선수로 본다.
        let first = game.userTeam.roster[0]
        game.players[first]?.age = 25
        let salaryBefore = game.players[first]!.contract.salary
        #expect(game.isExpiring(game.players[first]!))

        var clock = TestGame.start
        func next() -> Date { clock = clock.addingTimeInterval(3600); return clock }
        while game.phase != .offseason {
            try game.startMatch(now: next())
            game.runMatchToEnd()
        }
        // 시즌이 끝날 때 연봉이 오른다 (내려가지 않는다).
        #expect(game.players[first]!.contract.salary > salaryBefore)
        // 은퇴한 선수 자리에 온 임시 선수를 빼면 모두 계약 만료다.
        #expect(game.roster(of: game.userTeamID).filter { original.contains($0.id) }.allSatisfy { game.isExpiring($0) })
        #expect(game.news.contains { $0.text.hasPrefix("계약 만료") })

        // 한 명만 재계약한다: 요구 조건 그대로면 대부분 받아들인다.
        let keeper = game.players[first]!
        let demand = game.renewalDemand(keeper)
        try game.proposeRenewal(keeper.id, salary: demand.salary * 2, years: demand.years)
        #expect(throws: GameError.self) { try game.proposeRenewal(keeper.id, salary: demand.salary, years: 1) }
        // 답은 다음 경기가 끝난 뒤에 온다.
        #expect(game.players[first]!.contract.seasonsLeft == 0)
        try game.startMatch(now: next())
        game.runMatchToEnd()
        if !game.counters.isEmpty { try game.acceptCounter(game.counters[0].id) }
        let renewed = game.players[first]!.contract.seasonsLeft > 0

        while game.phase == .offseason {
            try game.startMatch(now: next())
            game.runMatchToEnd()
        }
        #expect(game.season == 2)
        #expect(game.userTeam.roster.contains(first) == renewed)
        // 떠난 자리는 임시 선수로 채워져 경기를 계속할 수 있다.
        #expect(game.currentLineup != nil)
        #expect(game.news.contains { $0.text.hasPrefix("계약이 끝나 떠난 선수") })
        Invariants.check(game, "계약 만료 뒤")
    }

    @Test func 오퍼를_수락하면_이적료를_받고_선수가_떠난다() throws {
        var game = TestGame.make(seed: 32)
        TestGame.addTokens(&game, 5_000_000, id: "a", at: TestGame.hours(1))
        try game.holdTryout()
        for candidate in game.candidates { try? game.sign(candidate: candidate.id) }
        game.generateIncomingOffers(count: 1)
        var offer = try #require(game.offers.first)
        if offer.swapPlayerID != nil {
            game.offers = []
            game.phase = .offseason
            game.generateIncomingOffers(count: 1)
            game.phase = .regular
            offer = try #require(game.offers.first)
        }
        let before = game.funds.balance
        let player = offer.playerID

        try game.respond(to: offer.id, .accept)
        #expect(game.funds.balance == before + offer.fee)
        #expect(game.players[player]?.teamID == offer.fromTeam)
        #expect(!game.userTeam.roster.contains(player))
        #expect(game.funds.seasonIncome["선수 판매"] == offer.fee)
    }

    @Test func 답하지_않은_오퍼는_다음_경기가_끝나면_사라진다() throws {
        var game = TestGame.make(seed: 33)
        game.generateIncomingOffers(count: 1)
        let offer = try #require(game.offers.first)
        #expect(game.offers.contains { $0.id == offer.id })
        try TestGame.playOne(&game, at: TestGame.hours(1))
        #expect(!game.offers.contains { $0.id == offer.id })
        #expect(game.news.contains { $0.text.contains("답이 없어 사라졌습니다") })
    }

    @Test func 트레이드_마감_뒤에는_이적_제안을_할_수_없다() throws {
        var game = TestGame.make(seed: 34)
        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(1))
        let target = game.roster(of: game.teams(in: .citizenAmateur)[0].id)[0]
        #expect(game.tradeWindowOpen)
        try game.proposeTransfer(target.id, fee: 100_000)
        game.round = Balance.tradeDeadlineRound
        #expect(!game.tradeWindowOpen)
        let other = game.roster(of: game.teams(in: .citizenAmateur)[1].id)[0]
        #expect(throws: GameError.self) { try game.proposeTransfer(other.id, fee: 100_000) }
        // FA 영입은 오프시즌에만
        #expect(game.freeAgentMarket.isEmpty)
    }

    @Test func 프로급_선수는_시민_구단에_오지_않는다() {
        let game = TestGame.make(seed: 35)
        let star = game.roster(of: game.teams(in: .pro)[0].id)[0]
        #expect(game.joinChance(star, salary: 1_000_000_000) == 0)
    }
}

@Suite struct BankruptcyTests {
    @Test func 자금이_0_아래로_5경기를_버티면_파산하고_새_구단으로_다시_시작한다() throws {
        var game = TestGame.make(seed: 41)
        game.funds.spend(50_000_000, .salary)
        #expect(game.funds.balance < 0)
        var clock = TestGame.start
        func next() -> Date { clock = clock.addingTimeInterval(3600); return clock }

        try game.startMatch(now: next())
        game.runMatchToEnd()
        #expect(game.financialState == .crisis(matchesLeft: 5))
        // 위기 중에는 시설 업그레이드와 영입을 할 수 없다.
        #expect(throws: GameError.self) { try game.holdTryout() }
        #expect(throws: GameError.self) { try game.upgrade(.training) }

        for left in [4, 3, 2, 1] {
            try game.startMatch(now: next())
            game.runMatchToEnd()
            #expect(game.financialState == .crisis(matchesLeft: left))
        }
        let oldName = game.userTeam.name
        let oldRoster = game.userTeam.roster
        try game.startMatch(now: next())
        game.runMatchToEnd()

        #expect(game.isBankrupt)
        #expect(game.financialState == .bankrupt)
        #expect(game.hallOfFame.map(\.name) == [oldName])
        #expect(oldRoster.allSatisfy { game.freeAgents.contains($0) })
        #expect(game.nextMatch() == nil)
        #expect(throws: GameError.self) { try game.startMatch(now: next()) }
        #expect(game.teams.filter(\.isUser).isEmpty)

        try game.foundNewClub(setup: .init(city: "부산", name: "부산 새출발 야구단"), now: next())
        #expect(!game.isBankrupt)
        #expect(game.userTeam.name == "부산 새출발 야구단")
        #expect(game.userTier == .citizenAmateur)
        #expect(game.funds.balance == 100_000)
        #expect(game.userTeam.roster.count == 14)
        #expect(game.teams.filter(\.isUser).count == 1)
        Invariants.check(game, "새 구단")
        try game.startMatch(now: next())
        game.runMatchToEnd()
    }

    @Test func 유예_중에_자금을_메우면_위기에서_벗어난다() throws {
        var game = TestGame.make(seed: 42)
        game.funds.spend(1_000_000, .salary)
        try TestGame.playOne(&game, at: TestGame.hours(1))
        #expect(game.financialState == .crisis(matchesLeft: 5))

        TestGame.addTokens(&game, 50_000_000, id: "a", at: TestGame.hours(2))
        game.refreshFinancialState()
        #expect(game.crisisMatchesLeft == nil)
        try game.holdTryout()
    }

    @Test func 자금이_다음_다섯_경기_연봉보다_적으면_경고한다() {
        var game = TestGame.make(seed: 43)
        TestGame.addTokens(&game, 100_000_000, id: "a", at: TestGame.hours(1))
        #expect(game.financialState == .healthy)
        game.funds.spend(game.funds.balance - 10, .facility)
        #expect(game.financialState == .warning)
    }
}

@Suite struct SoakTests {
    @Test func 여섯_시즌을_돌려도_세계가_무너지지_않는다() throws {
        var game = TestGame.make(seed: 2026)
        var manager = AutoManager(tokensPerMatch: 40_000_000)
        var tiers: [LeagueTier] = []
        var moved = 0

        while game.season <= 6 {
            let season = game.season
            let before = game.teams.map(\.tier)
            while game.season == season {
                try manager.playOne(&game)
                if game.isBankrupt {
                    try game.foundNewClub(setup: .init(city: "대전", name: "대전 재창단 \(season)"), now: manager.clock)
                }
            }
            moved += zip(before, game.teams.map(\.tier)).filter { $0 != $1 }.count
            tiers.append(game.userTier)
            Invariants.check(game, "\(game.season)시즌 시작")
            print("[소크] \(season)시즌: \(before[game.userTeamID].rawValue)부 \(String(format: "%.3f", game.lastWinRate[game.userTeamID] ?? 0)), 강도 \(String(format: "%.1f", game.strength(of: game.userTeamID))), 리그 CPU 평균 \(String(format: "%.1f", game.cpuAverageStrength(game.userTier))), 인지도 \(Int(game.userTeam.fame)), 자금 \(game.funds.balance / 1_000_000)M, 로스터 \(game.userTeam.roster.count)")
        }
        print("[소크] 내 팀 리그 변화: \(tiers.map(\.rawValue)), 리그를 옮긴 팀 수 합계 \(moved), 선수 \(game.players.count)명, FA \(game.freeAgents.count)명")
        // 승강이 실제로 일어난다.
        #expect(moved >= 20)
        // 충분히 투자하면 올라간다.
        #expect(tiers.last! < .citizenAmateur)
        // 선수 수가 끝없이 늘지 않는다.
        #expect(game.players.count < 1_800)
    }

    @Test func 같은_시드와_같은_입력이면_한_시즌_결과가_똑같다() throws {
        func run() throws -> Game {
            var game = TestGame.make(seed: 555)
            var manager = AutoManager(tokensPerMatch: 2_000_000)
            for _ in 0..<45 { try manager.playOne(&game) }
            return game
        }
        let first = try run()
        let second = try run()
        #expect(first == second)
    }

    @Test func 맞춰주기를_끄면_CPU_팀이_내_팀을_따라오지_않는다() throws {
        func leagueAverage(_ band: RubberBand) throws -> Double {
            var game = TestGame.make(seed: 808)
            TestGame.addTokens(&game, 500_000_000, id: "seed", at: TestGame.start)
            game.settings.rubberBand = band
            // 내 팀이 리그 상한 수준이다.
            for id in game.userTeam.roster {
                for key in Attributes.Key.allCases { game.players[id]?.attributes[key] = 40 }
                game.players[id]?.potential = 40
            }
            var clock = TestGame.start
            while game.season == 1 {
                clock = clock.addingTimeInterval(3600)
                try game.startMatch(now: clock)
                game.runMatchToEnd()
            }
            return game.cpuAverageStrength(.citizenAmateur)
        }
        let off = try leagueAverage(.off)
        let strong = try leagueAverage(.strong)
        print("[맞춰주기] 끄기 \(String(format: "%.2f", off)) / 강하게 \(String(format: "%.2f", strong))")
        // 강하게: 시즌당 한도(+5)만큼만 따라온다. 끄기: 그대로다.
        #expect(strong > off + 2)
        #expect(strong <= 30.9 + 5 + 1.5)
        #expect(abs(off - 30.9) < 2)
    }
}

@Suite struct UpperLeagueTests {
    /// 내 팀을 원하는 리그로 옮기고 그 리그 수준의 선수단으로 만든다.
    static func game(in tier: LeagueTier, ability: Double, seed: UInt64) -> Game {
        var game = TestGame.make(seed: seed)
        TestGame.addTokens(&game, 50_000_000_000, id: "seed", at: TestGame.start)
        let swap = game.teams(in: tier)[0].id
        game.teams[swap].tier = .citizenAmateur
        game.teams[game.userTeamID].tier = tier
        for id in game.userTeam.roster {
            for key in Attributes.Key.allCases { game.players[id]?.attributes[key] = ability }
            game.players[id]?.potential = ability
            game.players[id]?.age = 26
            game.players[id]?.contract = Contract(salary: 1_000_000, seasonsLeft: 3)
        }
        game.normalizeCPURoster(swap, leagueTarget: nil)
        game.startSeasonSchedules()
        return game
    }

    @Test func 프로_리그에서_두_시즌을_돌려도_무너지지_않고_상위_리그_기능이_돈다() throws {
        var game = Self.game(in: .pro, ability: 80, seed: 61)
        var manager = AutoManager(tokensPerMatch: 2_000_000_000)

        // TV 광고는 3부 이상에서만 할 수 있다.
        try game.promote(.tv)
        // 해외 스카우트는 스카우트 시설이 있어야 하고 1~2부에서만 보낼 수 있다.
        #expect(throws: GameError.self) { try game.sendScout(.overseas) }
        try game.upgrade(.scout)
        try game.sendScout(.overseas)

        var sawDraftBoard = false
        var foreignSigned = 0
        while game.season <= 2 {
            // 외국인 후보가 오면 한도(3명)까지 계약한다.
            for candidate in game.candidates where game.players[candidate.playerID]?.isForeign == true {
                let before = game.roster(of: game.userTeamID).filter(\.isForeign).count
                if before >= Balance.foreignPlayerLimit {
                    #expect(throws: GameError.self) { try game.sign(candidate: candidate.id) }
                } else if (try? game.sign(candidate: candidate.id)) != nil {
                    foreignSigned += 1
                }
            }
            if game.scoutTrip == nil, game.candidates.isEmpty { try? game.sendScout(.overseas) }
            if game.candidates.contains(where: { $0.source == .draft }) {
                sawDraftBoard = true
                #expect(game.phase == .offseason)
                #expect(game.friendliesPlayed >= Balance.draftAfterFriendly)
                #expect(game.candidates.filter { $0.source == .draft }.count == 5)
                let pick = try #require(game.candidates.first { $0.source == .draft })
                // 로스터가 가득 차 있으면 지명할 수 없다. 한 명을 내보내고 지명한다.
                if game.userTeam.roster.count >= Balance.rosterLimit(game.userTier, sport: .baseball) {
                    #expect(throws: GameError.self) { try game.sign(candidate: pick.id) }
                    let batters = game.roster(of: game.userTeamID).filter { !$0.isPitcher }
                    try game.release(try #require(batters.min { $0.ability < $1.ability }).id)
                }
                try game.sign(candidate: pick.id)
                // 드래프트는 한 명만 지명한다.
                #expect(!game.candidates.contains { $0.source == .draft })
                #expect(game.players[pick.playerID]?.teamID == game.userTeamID)
            }
            try manager.playOne(&game)
            #expect(!game.isBankrupt)
        }
        #expect(sawDraftBoard)
        #expect(foreignSigned >= 1)
        #expect(game.roster(of: game.userTeamID).filter(\.isForeign).count <= Balance.foreignPlayerLimit)
        #expect(game.userTeam.roster.count <= 28)
        Invariants.check(game, "프로 두 시즌 뒤")
    }

    @Test func 시민_리그에서는_해외_스카우트와_TV_광고를_쓸_수_없다() throws {
        var game = TestGame.make(seed: 62)
        TestGame.addTokens(&game, 5_000_000_000, id: "seed", at: TestGame.start)
        try game.upgrade(.scout)
        #expect(throws: GameError.self) { try game.sendScout(.overseas) }
        #expect(throws: GameError.self) { try game.promote(.tv) }
        try game.sendScout(.local)
        // 3경기 뒤에 후보가 온다.
        for hour in 1...2 { try TestGame.playOne(&game, at: TestGame.hours(Double(hour))) }
        #expect(game.candidates.isEmpty)
        try TestGame.playOne(&game, at: TestGame.hours(3))
        #expect(game.candidates.filter { $0.source == .scout }.count == 3)
        #expect(game.scoutTrip == nil)
    }

    @Test func 강등_조항이_있는_선수는_강등되면_이적료를_남기고_떠난다() {
        var game = Self.game(in: .amateur, ability: 55, seed: 63)
        for id in game.userTeam.roster { game.players[id]?.contract.relegationClause = true }
        let before = game.userTeam.roster
        let balance = game.funds.balance

        game.teams[game.userTeamID].tier = .citizenPro
        game.userRelegated(to: .citizenPro)

        let gone = before.filter { !game.userTeam.roster.contains($0) }
        #expect(!gone.isEmpty)
        #expect(gone.allSatisfy { id in
            guard let team = game.players[id]?.teamID else { return false }
            return game.teams[team].tier < .citizenPro
        })
        #expect(game.funds.balance > balance)
        #expect(game.funds.seasonIncome["선수 판매"] == game.funds.balance - balance)
        #expect(game.news.contains { $0.text.hasPrefix("강등 조항 발동") })
    }

    @Test func 시민_구단_때부터_함께한_선수는_프로에_오면_프랜차이즈_스타가_된다() {
        var game = Self.game(in: .semiPro, ability: 70, seed: 64)
        let veteran = game.userTeam.roster[0]
        let newcomer = game.userTeam.roster[1]
        game.players[veteran]?.joinedTier = 6
        game.players[newcomer]?.joinedTier = 2
        for id in game.userTeam.roster.dropFirst(2) { game.players[id]?.joinedTier = 3 }
        let fame = game.userTeam.fame
        let salary = game.players[veteran]!.contract.salary

        game.teams[game.userTeamID].tier = .pro
        game.userPromoted(to: .pro)

        #expect(game.players[veteran]?.isFranchiseStar == true)
        #expect(game.players[newcomer]?.isFranchiseStar == false)
        #expect(game.userTeam.fame >= fame + Balance.fameFranchiseStar)
        // 승격하면 연봉이 한 번 더 오른다.
        #expect(game.players[veteran]!.contract.salary > salary)
        #expect(game.bestTier == .pro)
    }

    @Test func 상위_리그_9위는_승강_플레이오프를_홈에서_시작하고_지면_강등된다() throws {
        var game = Self.game(in: .citizenSemiPro, ability: 12, seed: 65)
        let tier = LeagueTier.citizenSemiPro
        game.round = 36
        for league in LeagueTier.allCases {
            for index in game.standings[league.index].indices {
                game.standings[league.index][index].wins = 30 - index * 2
                game.standings[league.index][index].losses = 6 + index * 2
            }
        }
        // 내 팀을 9위로 만든다.
        let mine = game.standings[tier.index].firstIndex { $0.teamID == game.userTeamID }!
        let rows = Standings.ranked(game.standings[tier.index])
        let ninth = rows[8]
        game.standings[tier.index][mine].wins = ninth.wins
        game.standings[tier.index][mine].losses = ninth.losses
        let other = game.standings[tier.index].firstIndex { $0.teamID == ninth.teamID }!
        if other != mine {
            game.standings[tier.index][other].wins = 30 - mine * 2
            game.standings[tier.index][other].losses = 6 + mine * 2
        }
        #expect(game.rank(of: game.userTeamID) == 9)
        game.endRegularSeason()

        #expect(game.phase == .playoff)
        let series = try #require(game.series.first { $0.upperTeam == game.userTeamID })
        #expect(series.upperTier == tier)
        #expect(game.nextMatch()?.userIsHome == true)

        var clock = TestGame.start
        while game.phase == .playoff {
            clock = clock.addingTimeInterval(3600)
            try game.startMatch(now: clock)
            game.runMatchToEnd()
        }
        // 능력 12짜리 팀은 진다.
        #expect(game.userTier == .citizenAmateur)
        #expect(game.relegatedThisOffseason)
        for league in LeagueTier.allCases { #expect(game.teams(in: league).count == 10) }
    }

    @Test func 마지막_라운드에_파산해도_새_구단으로_이어서_할_수_있다() throws {
        var game = TestGame.make(seed: 66)
        // 내 자리가 2위로 끝나게 순위표를 채우고, 마지막 라운드에서 유예가 끝나게 한다.
        game.round = 35
        game.appliedForPromotion = true
        for league in LeagueTier.allCases {
            for index in game.standings[league.index].indices {
                let mine = game.standings[league.index][index].teamID == game.userTeamID
                game.standings[league.index][index].wins = mine ? 30 : 34 - index * 3
                game.standings[league.index][index].losses = 35 - game.standings[league.index][index].wins
            }
        }
        game.funds.spend(900_000_000, .salary)
        game.crisisMatchesLeft = 1
        var clock = TestGame.start
        clock = clock.addingTimeInterval(3600)
        try game.startMatch(now: clock)
        game.runMatchToEnd()

        #expect(game.isBankrupt)
        // 해체된 구단 때문에 플레이오프 단계에 걸려 있으면 안 된다.
        #expect(game.phase == .offseason)
        #expect(game.series.isEmpty)

        try game.foundNewClub(setup: .init(city: "광주", name: "광주 새출발 야구단"), now: clock)
        #expect(game.nextMatch()?.kind == .friendly)
        while game.season == 1 {
            clock = clock.addingTimeInterval(3600)
            TestGame.addTokens(&game, 1_000_000, id: "t\(clock.timeIntervalSince1970)", at: clock)
            try game.startMatch(now: clock)
            game.runMatchToEnd()
        }
        #expect(game.phase == .regular)
        #expect(game.nextMatch()?.kind == .regular)
        Invariants.check(game, "파산 뒤 새 시즌")
    }
}

@Suite struct OpponentRosterTests {
    static func isPlayable(_ game: Game, _ id: TeamID) -> Bool {
        LineupBuilder.build(team: game.teams[id], players: game.players) != nil
    }

    /// 야수를 8명만 남긴다.
    static func dropBatters(_ game: inout Game, _ id: TeamID) {
        let batters = game.roster(of: id).filter { !$0.isPitcher }
        for player in batters.dropFirst(8) { game.moveToFreeAgency(player.id) }
    }

    @Test func 친선_상대가_로스터는_꽉_찼는데_야수가_모자라도_오프시즌이_멈추지_않는다() throws {
        var game = TestGame.make(seed: 31)
        var manager = AutoManager(tokensPerMatch: 2_000_000)
        try ContractTests.toOffseason(&game, &manager)
        let opponent = try #require(game.nextMatch()).opponent
        let tier = game.teams[opponent].tier

        // 야수 8명에 투수로 정원을 꽉 채운 상대를 만든다.
        Self.dropBatters(&game, opponent)
        while game.teams[opponent].roster.count < Balance.rosterLimit(tier, sport: .baseball) {
            let pitcher = game.makePlayer(PlayerFactory.Spec(position: .reliever, tier: tier, season: game.season))
            game.add(pitcher.id, to: opponent)
        }
        #expect(!Self.isPlayable(game, opponent))

        try manager.playOne(&game)
        #expect(game.friendliesPlayed == 1)
        #expect(Self.isPlayable(game, opponent))
        #expect(game.teams[opponent].roster.count <= Balance.rosterLimit(tier, sport: .baseball))
    }

    @Test func 윗_리그_로스터를_그대로_들고_강등된_구단도_경기를_치를_수_있게_정리된다() throws {
        var game = TestGame.make(seed: 31)
        let team = try #require(game.teams(in: .amateur).first { !$0.isUser }).id
        #expect(game.teams[team].roster.count == Balance.rosterLimit(.amateur, sport: .baseball))

        // 22명 그대로 18명 정원인 리그로 내려가고, 야수가 떠나 8명만 남는다.
        game.teams[team].tier = .citizenPro
        Self.dropBatters(&game, team)
        #expect(game.teams[team].roster.count >= Balance.rosterLimit(.citizenPro, sport: .baseball))
        #expect(!Self.isPlayable(game, team))

        game.ensurePlayable(team)
        #expect(Self.isPlayable(game, team))
        #expect(game.teams[team].roster.count <= Balance.rosterLimit(.citizenPro, sport: .baseball))
        #expect(game.roster(of: team).filter { $0.isPitcher }.count >= Balance.minPitchers)
    }
}

@Suite struct OffseasonEdgeTests {
    /// 마지막 친선 경기만 남긴 오프시즌으로 간다.
    static func beforeLastFriendly(seed: UInt64) throws -> (Game, AutoManager) {
        var game = TestGame.make(seed: seed)
        var manager = AutoManager(tokensPerMatch: 2_000_000)
        try ContractTests.toOffseason(&game, &manager)
        while game.friendliesPlayed < Balance.friendliesPerOffseason - 1 { try manager.playOne(&game) }
        return (game, manager)
    }

    /// 계약이 끝난 선수 한 명에게 역제안이 와 있는 상태로 만든다.
    static func addCounter(_ game: inout Game) throws -> PlayerID {
        let player = try #require(game.roster(of: game.userTeamID).first { !$0.isPitcher })
        game.players[player.id]?.contract.seasonsLeft = 0
        game.proposals.removeAll { $0.playerID == player.id }
        game.counters.removeAll { $0.playerID == player.id }
        game.counters.append(Proposal(
            id: game.newMarketID(), kind: .renewal, playerID: player.id, salary: 123_000, years: 2, fee: 0))
        return player.id
    }

    func play(_ game: inout Game, _ clock: inout Date) throws {
        clock = clock.addingTimeInterval(3600)
        try game.startMatch(now: clock)
        game.runMatchToEnd()
    }

    @Test func 마지막_친선_경기_뒤에_남은_역제안은_새_시즌_첫_경기까지_답할_수_있다() throws {
        var (game, manager) = try Self.beforeLastFriendly(seed: 31)
        let id = try Self.addCounter(&game)
        try play(&game, &manager.clock)

        #expect(game.phase == .regular)
        #expect(game.players[id]?.teamID == game.userTeamID)
        let counter = try #require(game.counters.first { $0.playerID == id })
        // 기다려 주는 동안 새 제안으로 시간을 끌 수는 없다.
        #expect(throws: GameError.self) { try game.proposeRenewal(id, salary: 1_000, years: 1) }

        try game.acceptCounter(counter.id)
        #expect(game.players[id]?.contract.seasonsLeft == 2)
        #expect(game.players[id]?.contract.salary == 123_000)
        try play(&game, &manager.clock)
        #expect(game.players[id]?.teamID == game.userTeamID)
    }

    @Test func 역제안에_끝내_답하지_않으면_새_시즌_첫_경기_뒤에_떠난다() throws {
        var (game, manager) = try Self.beforeLastFriendly(seed: 31)
        let id = try Self.addCounter(&game)
        try play(&game, &manager.clock)
        #expect(game.players[id]?.teamID == game.userTeamID)

        try play(&game, &manager.clock)
        #expect(game.players[id]?.teamID == nil)
        #expect(game.counters.isEmpty)
        #expect(game.currentLineup != nil)
        #expect(game.roster(of: game.userTeamID).allSatisfy { $0.contract.seasonsLeft > 0 })
    }

    @Test func 시즌_중_재계약은_남은_시즌에_새_기간을_더한다() throws {
        var game = TestGame.make(seed: 31)
        let player = try #require(game.roster(of: game.userTeamID).first)
        game.players[player.id]?.contract.seasonsLeft = 1
        game.counters.append(Proposal(
            id: game.newMarketID(), kind: .renewal, playerID: player.id, salary: 50_000, years: 2, fee: 0))
        try game.acceptCounter(try #require(game.counters.first).id)
        #expect(game.players[player.id]?.contract.seasonsLeft == 3)
    }

    @Test func 스카우트_출장과_데려온_후보는_새_시즌으로_이어진다() throws {
        var (game, manager) = try Self.beforeLastFriendly(seed: 31)
        game.teams[game.userTeamID].scoutLevel = 1
        TestGame.addTokens(&game, 500_000_000, id: "scout", at: manager.clock)
        try game.sendScout(.national)
        try play(&game, &manager.clock)
        #expect(game.phase == .regular)
        #expect(game.scoutTrip?.matchesLeft == 2)

        try play(&game, &manager.clock)
        try play(&game, &manager.clock)
        #expect(game.scoutTrip == nil)
        #expect(game.candidates.contains { $0.source == .scout })
    }

    @Test func 마지막_친선_경기_뒤에_돌아온_스카우트_후보도_사라지지_않는다() throws {
        var (game, manager) = try Self.beforeLastFriendly(seed: 31)
        game.scoutTrip = ScoutTrip(region: .local, matchesLeft: 1)
        try play(&game, &manager.clock)
        #expect(game.phase == .regular)
        #expect(game.candidates.contains { $0.source == .scout })
        #expect(game.offers.isEmpty)
        #expect(!game.candidates.contains { $0.source == .draft })
    }

    @Test func 강등되면_해외_스카우트는_취소되고_비용을_돌려받는다() throws {
        var game = UpperLeagueTests.game(in: .semiPro, ability: 68, seed: 71)
        try game.upgrade(.scout)
        let before = game.funds.balance
        try game.sendScout(.overseas)
        #expect(game.funds.balance < before)

        game.teams[game.userTeamID].tier = .amateur
        game.userRelegated(to: .amateur)
        #expect(game.scoutTrip == nil)
        #expect(game.funds.balance == before)
    }

    @Test func 강등_뒤_스폰서_수입은_다음_시즌_동안_절반이고_그_뒤에_돌아온다() throws {
        var game = UpperLeagueTests.game(in: .amateur, ability: 45, seed: 72)
        var manager = AutoManager(tokensPerMatch: 2_000_000_000)
        // 4부 한 팀과 자리를 바꿔 강등된다.
        let up = game.teams(in: .citizenPro)[0].id
        game.teams[up].tier = .amateur
        game.teams[game.userTeamID].tier = .citizenPro
        game.userRelegated(to: .citizenPro)
        game.startOffseason()
        while game.phase == .offseason { try manager.playOne(&game) }
        #expect(game.sponsorPenaltySeasons == 1)

        // 정규시즌 첫 경기의 스폰서 수입이 절반이다.
        try game.startMatch(now: manager.clock.addingTimeInterval(3600))
        game.runMatchToEnd()
        // 스폰서 수입은 경기 결과로 인지도가 바뀐 뒤에 계산된다.
        let expected = Int(game.userTeam.fame) * Balance.sponsorPerFame(game.userTier) / 2
        #expect(expected > 0)
        #expect(game.funds.seasonIncome["스폰서"] == expected)

        while game.phase == .regular { try manager.playOne(&game) }
        #expect(game.sponsorPenaltySeasons == 0)
    }

    @Test func FA_여러_명에게_한꺼번에_제안해도_외국인_한도를_넘지_않는다() throws {
        var game = UpperLeagueTests.game(in: .semiPro, ability: 68, seed: 73)
        game.startOffseason()
        game.teams[game.userTeamID].fame = 100_000
        // 이미 외국인 2명이 있는 팀으로 만든다. 로스터에는 빈자리가 넉넉하다.
        #expect(game.userTeam.roster.count + 6 <= Balance.rosterLimit(.semiPro, sport: .baseball))
        for player in game.roster(of: game.userTeamID).prefix(2) { game.players[player.id]?.isForeign = true }
        for _ in 0..<6 {
            var spec = PlayerFactory.Spec(position: .left, tier: .semiPro, season: game.season)
            spec.foreign = true
            let player = game.makePlayer(spec)
            game.players[player.id]?.contract.seasonsLeft = 0
            game.freeAgents.append(player.id)
            try game.proposeFreeAgent(
                player.id, salary: Balance.marketSalary(ability: player.ability) * 4, years: 1)
        }
        var clock = TestGame.start
        try play(&game, &clock)
        let foreign = game.roster(of: game.userTeamID).filter(\.isForeign).count
        #expect(foreign == Balance.foreignPlayerLimit)
    }

    @Test func 시즌_막판에_다시_창단한_구단은_순위_상금을_받지_않는다() throws {
        var game = TestGame.make(seed: 74)
        var manager = AutoManager(tokensPerMatch: 2_000_000)
        while game.round < 34 { try manager.playOne(&game) }
        game.goBankrupt()
        try game.foundNewClub(setup: .init(city: "광주", name: "광주 새출발 야구단"), now: manager.clock)
        // 두 경기만 이기고 승률 1위가 된 상황.
        let tier = game.userTier.index
        let row = try #require(game.standings[tier].firstIndex { $0.teamID == game.userTeamID })
        game.youthBoost = 3
        while game.phase == .regular {
            game.standings[tier][row].wins = 2
            game.standings[tier][row].losses = 0
            manager.clock = manager.clock.addingTimeInterval(3600)
            try game.startMatch(now: manager.clock)
            // 마지막 공 직전에 순위표를 다시 맞춘다.
            game.runMatchToEnd()
        }
        #expect(game.funds.seasonIncome["상금·지원금"] == nil)
        #expect(game.news.contains { $0.text.contains("시즌 도중에 창단") })
    }

    @Test func 다시_창단하면_지난_구단의_강등_상태와_유소년_효과가_남지_않는다() throws {
        var game = TestGame.make(seed: 75)
        game.relegatedThisOffseason = true
        game.youthBoost = 2
        game.sponsorPenaltySeasons = 1
        game.goBankrupt()
        try game.foundNewClub(setup: .init(city: "광주", name: "광주 새출발 야구단"), now: TestGame.start)
        #expect(!game.relegatedThisOffseason)
        #expect(game.youthBoost == 0)
        #expect(game.sponsorPenaltySeasons == 0)
    }

    @Test func 윗_리그_구단과의_친선_경기에는_콜드게임이_없다() throws {
        var game = UpperLeagueTests.game(in: .citizenPro, ability: 50, seed: 76)
        game.startOffseason()
        var seen: Set<Bool> = []
        for played in 0..<Balance.friendliesPerOffseason {
            var copy = game
            copy.friendliesPlayed = played
            let opponent = try #require(copy.nextMatch()).opponent
            let upper = min(copy.userTier, copy.teams[opponent].tier)
            try copy.startMatch(now: TestGame.start.addingTimeInterval(3600))
            // 콜드게임은 두 구단이 모두 시민 구단일 때만 있다.
            #expect(copy.live?.state.rules.coldGame == upper.isCitizen)
            #expect(copy.live?.tier == upper)
            seen.insert(upper.isCitizen)
        }
        #expect(seen.count == 2)
    }

    @Test func 계약이_끝난_채_팔린_선수가_트레이드로_돌아와도_곧바로_떠나지_않는다() throws {
        var game = TestGame.make(seed: 77)
        var clock = TestGame.start
        let buyer = try #require(game.teams.first { !$0.isUser && $0.tier == game.userTier }).id
        let mine = game.roster(of: game.userTeamID).filter { !$0.isPitcher }
        // 맞교환으로 한 명이 나가도 야수 9명이 남게 한 명을 더 둔다.
        let extra = game.makePlayer(PlayerFactory.Spec(position: .left, tier: game.userTier, season: game.season))
        game.add(extra.id, to: game.userTeamID)
        // 계약이 끝난 선수 둘이 다른 구단으로 갔다.
        for player in mine.prefix(2) {
            game.players[player.id]?.contract.seasonsLeft = 0
            game.add(player.id, to: buyer)
            #expect(game.players[player.id]?.contract.seasonsLeft == 1)
        }
        // 한 명은 이적 오퍼의 맞교환으로, 한 명은 그대로 돌아온다.
        game.offers.append(TransferOffer(
            id: game.newMarketID(), playerID: mine[2].id, fromTeam: buyer, fee: 0, swapPlayerID: mine[0].id))
        try game.respond(to: try #require(game.offers.last).id, .accept)
        game.add(mine[1].id, to: game.userTeamID)

        try play(&game, &clock)
        #expect(game.players[mine[0].id]?.teamID == game.userTeamID)
        #expect(game.players[mine[1].id]?.teamID == game.userTeamID)
    }
}
