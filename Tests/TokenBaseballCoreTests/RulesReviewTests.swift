import Foundation
import Testing
@testable import TokenBaseballCore

/// 전문가 검토 뒤에 고친 규칙들.
enum ReviewGame {
    static func football(seed: UInt64 = 81) -> Game {
        Game.newGame(setup: .init(city: "서울", name: "서울 시민 FC"), now: TestGame.start, seed: seed, sport: .football)
    }

    /// 모든 리그의 순위표를 채운다. 내 구단은 6부에서 `userRank`위.
    static func fillStandings(_ game: inout Game, userRank: Int) {
        for tier in LeagueTier.allCases {
            var order = game.standings[tier.index].map(\.teamID).filter { $0 != game.userTeamID }
            if tier == game.userTier { order.insert(game.userTeamID, at: userRank - 1) }
            for (place, id) in order.enumerated() {
                let index = game.standings[tier.index].firstIndex { $0.teamID == id }!
                game.standings[tier.index][index].wins = order.count - place
                game.standings[tier.index][index].losses = game.roundsPerSeason - (order.count - place)
            }
        }
        game.round = game.roundsPerSeason
    }
}

@Suite struct FootballPromotionTests {
    @Test func 잉글랜드식으로_세_팀이_올라가고_세_팀이_내려간다() {
        var game = ReviewGame.football()
        ReviewGame.fillStandings(&game, userRank: 8)
        let before = LeagueTier.allCases.map { tier in game.rankedStandings(tier).map(\.teamID) }
        game.endRegularSeason()
        #expect(game.phase == .offseason)
        for tier in LeagueTier.allCases {
            #expect(game.teams(in: tier).count == Balance.teamsPerLeague(.football))
            let ranked = before[tier.index]
            if let lower = tier.lower {
                // 맨 아래 세 팀(18~20위)은 자동 강등
                #expect(ranked.suffix(3).allSatisfy { game.teams[$0].tier == lower })
                #expect(ranked.dropLast(3).allSatisfy { game.teams[$0].tier != lower })
            }
            if let upper = tier.upper {
                // 1위와 2위는 자동 승격, 3~6위 중 플레이오프를 이긴 한 팀이 승격
                #expect(game.teams[ranked[0]].tier == upper)
                #expect(game.teams[ranked[1]].tier == upper)
                #expect(ranked[2...5].filter { game.teams[$0].tier == upper }.count == 1)
                #expect(ranked[6...].allSatisfy { game.teams[$0].tier != upper })
            }
        }
    }

    @Test func 열_팀_리그로_치른_시즌은_예전대로_두_팀이_오르내린다() {
        var game = Game.newGame(
            setup: .init(city: "서울", name: "서울 시민 FC"), now: TestGame.start, seed: 81, sport: .football, leagueSize: 10)
        ReviewGame.fillStandings(&game, userRank: 8)
        let before = LeagueTier.allCases.map { tier in game.rankedStandings(tier).map(\.teamID) }
        game.endRegularSeason()
        #expect(game.phase == .offseason)
        for tier in LeagueTier.allCases {
            #expect(game.teams(in: tier).count == 10)
            let ranked = before[tier.index]
            if let lower = tier.lower {
                #expect(ranked.suffix(2).allSatisfy { game.teams[$0].tier == lower })
                #expect(ranked.dropLast(2).allSatisfy { game.teams[$0].tier != lower })
            }
            if let upper = tier.upper {
                #expect(game.teams[ranked[0]].tier == upper)
                #expect(ranked[1...4].filter { game.teams[$0].tier == upper }.count == 1)
                #expect(ranked[5...].allSatisfy { game.teams[$0].tier != upper })
            }
        }
    }

    @Test func 구장_등급이_모자라면_승격_자격이_다음_순위로_넘어간다() {
        var game = ReviewGame.football()
        ReviewGame.fillStandings(&game, userRank: 1)
        #expect(game.promotionStadiumRequirement == 2)
        #expect(game.userTeam.stadiumLevel == 1)
        #expect(throws: GameError.self) { try game.applyForPromotion() }
        game.endRegularSeason()
        #expect(game.phase == .offseason)
        #expect(game.userTier == .citizenAmateur)
        #expect(game.news.contains { $0.text.contains("구장 등급") })
    }

    @Test func 승격_플레이오프는_준결승_두_경기_합산과_중립_결승이다() throws {
        var game = ReviewGame.football(seed: 82)
        for id in game.userTeam.roster {
            for key in Attributes.Key.all(for: .football) { game.players[id]?.attributes[key] = 60 }
            game.players[id]?.potential = 60
        }
        game.teams[game.userTeamID].stadiumLevel = 2
        // 3위로 마치면 플레이오프다 (1위와 2위는 바로 올라간다).
        ReviewGame.fillStandings(&game, userRank: 3)
        game.endRegularSeason()
        #expect(game.phase == .playoff)

        let semi = try #require(game.series.first { $0.involves(game.userTeamID) })
        #expect(semi.kind == .twoLegs)
        #expect(semi.upperTeam == game.userTeamID)
        // 1차전은 순위가 낮은 팀의 홈이고, 비겨도 끝난다.
        #expect(game.nextMatch()?.label == "승격 플레이오프 준결승 1차전")
        #expect(game.nextMatch()?.userIsHome == false)
        try game.startMatch(now: TestGame.hours(1))
        #expect(game.liveFootball?.state.rules.mustHaveWinner == false)
        game.runMatchToEnd()
        let first = try #require(game.series.first { $0.involves(game.userTeamID) })
        #expect(first.legs == 1)
        #expect(!first.isDecided)

        // 2차전은 내 홈이고, 합산이 같으면 연장으로 간다.
        #expect(game.nextMatch()?.label == "승격 플레이오프 준결승 2차전")
        #expect(game.nextMatch()?.userIsHome == true)
        try game.startMatch(now: TestGame.hours(2))
        let rules = try #require(game.liveFootball?.state.rules)
        #expect(rules.mustHaveWinner)
        #expect(rules.firstLegHome == first.upperGoals)
        #expect(rules.firstLegAway == first.lowerGoals)
        game.runMatchToEnd()

        // 능력 60인 구단은 6부에서 이긴다: 결승은 중립 구장 단판.
        #expect(game.nextMatch()?.label == "승격 플레이오프 결승")
        try game.startMatch(now: TestGame.hours(3))
        #expect(game.liveFootball?.state.rules.neutral == true)
        #expect(game.liveFootball?.state.edgePoints == 0)
        game.runMatchToEnd()
        #expect(game.phase == .offseason)
        #expect(game.userTier == .citizenSemiPro)
    }

    @Test func 합산이_같으면_승부차기_승자가_올라간다() {
        var game = ReviewGame.football()
        game.series = [PlayoffSeries(upperTier: .pro, upperTeam: 3, lowerTeam: 4, format: .twoLegs, stage: .semi)]
        game.recordPlayoffGame(0, home: 4, homeScore: 2, awayScore: 1)
        #expect(!game.series[0].isDecided)
        game.recordPlayoffGame(0, home: 3, homeScore: 1, awayScore: 0, shootoutHomeWon: false)
        #expect(game.series[0].upperGoals == 2 && game.series[0].lowerGoals == 2)
        #expect(game.series[0].winner == 4)

        game.series = [PlayoffSeries(upperTier: .pro, upperTeam: 3, lowerTeam: 4, format: .twoLegs, stage: .semi)]
        game.recordPlayoffGame(0, home: 4, homeScore: 0, awayScore: 0)
        game.recordPlayoffGame(0, home: 3, homeScore: 3, awayScore: 1)
        #expect(game.series[0].winner == 3)
    }

    @Test func 야구_와일드카드는_이위가_한_번만_이기면_된다() {
        var series = PlayoffSeries(upperTier: .pro, upperTeam: 1, lowerTeam: 2, format: .wildcard, stage: .wildcard)
        #expect(series.nextHome == 1)
        series.lowerWins = 1
        #expect(!series.isDecided)
        #expect(series.nextHome == 1)
        series.upperWins = 1
        #expect(series.winner == 1)
        var upset = PlayoffSeries(upperTier: .pro, upperTeam: 1, lowerTeam: 2, format: .wildcard, stage: .wildcard)
        upset.lowerWins = 2
        #expect(upset.winner == 2)
    }
}

@Suite struct FootballRulesReviewTests {
    @Test func 출장_정지_선수는_다음_리그_경기에_나오지_못한다() throws {
        var game = ReviewGame.football(seed: 83)
        let lineup = try #require(FootballLineupBuilder.build(team: game.userTeam, players: game.players))
        let banned = lineup.starters[5].id
        game.players[banned]?.suspendedMatches = 1
        let next = try #require(FootballLineupBuilder.build(team: game.userTeam, players: game.players))
        #expect(!next.starters.contains { $0.id == banned })
        #expect(!next.bench.contains(banned))

        try TestGame.playOne(&game, at: TestGame.hours(1))
        #expect(game.players[banned]?.suspendedMatches == nil)
        #expect((game.players[banned]?.football?.games ?? 0) == 0)
    }

    @Test func 이적_기간은_여름과_겨울_두_번이다() {
        var game = ReviewGame.football()
        game.round = 0
        #expect(game.tradeWindowOpen)
        game.round = Balance.footballSummerWindowRounds
        #expect(!game.tradeWindowOpen)
        game.round = Balance.footballWinterWindow.lowerBound
        #expect(game.tradeWindowOpen)
        game.round = Balance.footballWinterWindow.upperBound + 1
        #expect(!game.tradeWindowOpen)
        // 야구는 트레이드 마감 전까지 열려 있다.
        var baseball = TestGame.make()
        baseball.round = 10
        #expect(baseball.tradeWindowOpen)
    }

    @Test func 득점과_홈_승률이_실제_축구_범위에_든다() {
        let game = ReviewGame.football(seed: 84)
        var rng = SeededRNG(seed: 7)
        var matches = 0, goals = 0, homeWins = 0, awayWins = 0, reds = 0
        for tier in [LeagueTier.pro, .citizenAmateur] {
            for round in game.schedules[tier.index] {
                for fixture in round {
                    guard var match = game.makeFootballMatch(
                        home: fixture.home, away: fixture.away, kind: .regular, seed: rng.next())
                    else { continue }
                    match.runToEnd()
                    matches += 1
                    goals += match.home.goals + match.away.goals
                    reds += match.home.redCards + match.away.redCards
                    if match.home.goals > match.away.goals { homeWins += 1 }
                    if match.home.goals < match.away.goals { awayWins += 1 }
                }
            }
        }
        let n = Double(matches)
        #expect((2.4...3.2).contains(Double(goals) / n))
        #expect((0.38...0.50).contains(Double(homeWins) / n))
        #expect(Double(awayWins) / n > 0.24)
        #expect(Double(reds) / n < 0.2)
    }

    @Test func 골키퍼는_늦게까지_크고_필드_선수는_일찍_멈춘다() {
        #expect(Balance.ageGrowthFactor(29, position: .forward) == 0)
        #expect(Balance.ageGrowthFactor(29, position: .goalkeeper) > 0)
        #expect(Balance.ageGrowthFactor(29, position: .shortstop) > 0)
        #expect(Balance.careerTrainingAgeLimit(.goalkeeper) > Balance.careerTrainingAgeLimit(.forward))
        #expect(Balance.careerForcedRetirementAge(.goalkeeper) > Balance.careerForcedRetirementAge(.forward))
        #expect(Attributes.weights(for: .forward).contains { $0.0 == .stamina })
    }
}

@Suite struct BaseballRulesReviewTests {
    @Test func 리그가_달라도_득점_환경이_비슷하다() {
        let game = TestGame.make(seed: 85)
        var rng = SeededRNG(seed: 9)
        for tier in [LeagueTier.pro, .citizenAmateur] {
            var teamGames = 0, runs = 0, homeRuns = 0, walks = 0, appearances = 0
            for round in game.schedules[tier.index].prefix(18) {
                for fixture in round {
                    guard var match = game.makeMatch(
                        home: fixture.home, away: fixture.away, kind: .regular, tier: tier, seed: rng.next())
                    else { continue }
                    match.runToEnd()
                    for side in [match.home, match.away] {
                        teamGames += 1
                        runs += side.runs
                        homeRuns += side.batters.reduce(0) { $0 + $1.line.homeRuns }
                        walks += side.batters.reduce(0) { $0 + $1.line.walks }
                        appearances += side.batters.reduce(0) { $0 + $1.line.plateAppearances }
                        // 선발이 5이닝(콜드게임은 4이닝)을 못 채웠으면 승리 투수가 아니다.
                        if side.pitchers[0].line.wins > 0 { #expect(side.pitchers[0].line.outs >= 12) }
                    }
                }
            }
            let n = Double(teamGames)
            #expect((3.4...5.4).contains(Double(runs) / n))
            // 예전에는 1부에서 팀당 2.4개씩 나왔다.
            #expect((0.5...1.4).contains(Double(homeRuns) / n))
            #expect((0.07...0.11).contains(Double(walks) / Double(appearances)))
        }
    }

    @Test func 쉬어야_하는_선발은_다음_경기_선발로_지정할_수_없다() throws {
        var game = TestGame.make(seed: 86)
        try TestGame.playOne(&game, at: TestGame.hours(1))
        let roster = game.roster(of: game.userTeamID)
        let justPitched = try #require(roster.first { $0.lastStartGame == game.userTeam.gamesPlayed - 1 })
        #expect(throws: GameError.self) { try game.setNextStarter(justPitched.id) }
        let rested = try #require(roster.first { $0.position == .starter && $0.id != justPitched.id })
        try game.setNextStarter(rested.id)
    }

    @Test func 많이_던졌거나_연투한_불펜은_다음_경기에_맨_뒤로_간다() {
        var player = TestGame.make().roster(of: 0).first { $0.position == .reliever }!
        #expect(!player.needsReliefRest(game: 5))
        player.lastReliefGame = 4
        player.lastReliefPitches = 30
        #expect(player.needsReliefRest(game: 5))
        #expect(!player.needsReliefRest(game: 6))
        player.lastReliefPitches = 10
        player.reliefStreak = 1
        #expect(!player.needsReliefRest(game: 5))
        player.reliefStreak = 2
        #expect(player.needsReliefRest(game: 5))
    }

    @Test func 승강_플레이오프에서는_에이스가_일차전에_나온다() {
        var game = TestGame.make(seed: 87)
        let a = game.teams(in: .citizenSemiPro)[8].id, b = game.teams(in: .citizenAmateur)[1].id
        for id in game.teams[a].roster where game.players[id]?.position == .starter {
            game.players[id]?.lastStartGame = game.teams[a].gamesPlayed
        }
        game.series = [PlayoffSeries(upperTier: .citizenSemiPro, upperTeam: a, lowerTeam: b)]
        game.resetRotation(game.series[0])
        let ace = game.roster(of: a).filter { $0.position == .starter }.max { $0.ability < $1.ability }
        #expect(LineupBuilder.build(team: game.teams[a], players: game.players)?.starter == ace?.id)
    }
}

@Suite struct CareerReviewTests {
    @Test func 어떤_훈련이든_능력이_같은_양만큼_오른다() throws {
        for position in [Position.starter, .shortstop, .goalkeeper, .midfielder] {
            var game = TestCareer.make(position, seed: 88)
            TestGame.addTokens(&game, 80_000_000, id: "a", at: TestGame.hours(1))
            for key in game.careerTrainableKeys.prefix(2) {
                let before = try #require(game.myPlayer).ability
                try game.trainCareer(key)
                #expect(abs(try #require(game.myPlayer).ability - before - game.careerTrainingStep) < 0.0001)
            }
        }
    }

    @Test func 리그_수준을_넘어도_타고난_한계까지는_훈련할_수_있다() throws {
        var game = TestCareer.make(.center, seed: 89)
        TestGame.addTokens(&game, 500_000_000, id: "a", at: TestGame.hours(1))
        let id = try #require(game.career?.playerID)
        // 6부 강도 범위의 위쪽 끝을 훌쩍 넘긴 선수.
        let high = Balance.strengthRange(.citizenAmateur).upperBound + 20
        for key in [Attributes.Key.contact, .power, .eye, .speed, .fielding, .arm] { game.players[id]?.attributes[key] = high }
        game.players[id]?.potential = 90
        #expect(game.userTier == .citizenAmateur)
        let before = try #require(game.myPlayer).ability
        try game.trainCareer(.contact)
        #expect(try #require(game.myPlayer).ability > before)
        // 한계는 그대로 막는다.
        let reached = try #require(game.myPlayer).ability
        game.players[id]?.potential = reached
        #expect(throws: GameError.self) { try game.trainCareer(.contact) }
    }

    @Test func 짧게_뛴_교체_출전은_감독_신뢰가_조금만_움직인다() {
        #expect(Game.careerTrustChange(rating: 6.6, minutes: 20) == 0.5)
        #expect(Game.careerTrustChange(rating: 6.6, minutes: 80) == 0)
        #expect(Game.careerTrustChange(rating: 5.5, minutes: 20) == -0.5)
        #expect(Game.careerTrustChange(rating: 7.5) > 2)
    }

    @Test func 선발_투수는_등판하지_않는_날에_훈련을_한_번_더_한다() throws {
        var game = TestCareer.make(.starter, seed: 90)
        var auto = CareerAuto()
        auto.tokensPerMatch = 0
        for _ in 0..<4 {
            try auto.playOne(&game)
            let pitched = game.career?.lastRating != nil
            #expect(game.career?.sessionsLeft == Balance.careerSessionsPerMatch + (pitched ? 0 : 1))
        }
    }
}

@Suite struct FootballReviewFollowUpTests {
    @Test func 합산_이차전은_그날_점수가_달라도_승부차기_승자가_이긴다() throws {
        // 1차전에서 원정 팀이 2:1로 이긴 뒤의 2차전: 홈 팀이 1:0으로 이기면 합산 2:2라 승부차기로 간다.
        let game = ReviewGame.football(seed: 91)
        let home = game.teams(in: .citizenAmateur)[0].id, away = game.teams(in: .citizenAmateur)[1].id
        var rules = FootballRules(mustHaveWinner: true, homeEdge: 0.01)
        rules.firstLegHome = 1
        rules.firstLegAway = 2
        var sawAwayShootoutWin = false, sawUnequalScoreShootout = false
        for seed in 1...400 as ClosedRange<UInt64> {
            guard var match = game.makeFootballMatch(home: home, away: away, kind: .playoff, seed: seed, rules: rules)
            else { continue }
            match.runToEnd()
            guard match.wentToShootout else { continue }
            // 승부차기는 합산이 같을 때만 간다.
            #expect(match.home.goals + 1 == match.away.goals + 2)
            sawUnequalScoreShootout = true
            let shootoutHome = match.home.shootoutGoals > match.away.shootoutGoals
            #expect(match.result == (shootoutHome ? .homeWin : .awayWin))
            if !shootoutHome { sawAwayShootoutWin = true }
        }
        #expect(sawUnequalScoreShootout)
        #expect(sawAwayShootoutWin)
    }

    @Test func 출장_정지는_친선_경기에_적용되지_않고_플레이오프에서도_채워진다() throws {
        var game = ReviewGame.football(seed: 92)
        let lineup = try #require(FootballLineupBuilder.build(team: game.userTeam, players: game.players))
        let banned = lineup.starters[3].id
        game.players[banned]?.suspendedMatches = 1
        let friendly = try #require(FootballLineupBuilder.build(
            team: game.userTeam, players: game.players, ignoreSuspensions: true))
        #expect(friendly.starters.contains { $0.id == banned })

        // 플레이오프 경기도 정지를 채운다.
        let other = game.teams(in: .citizenAmateur).first { $0.id != game.userTeamID }!.id
        var match = try #require(game.makeFootballMatch(home: game.userTeamID, away: other, kind: .playoff, seed: 3))
        match.runToEnd()
        game.applyFootball(match, tier: .citizenAmateur, countsForStandings: false, competitive: true)
        #expect(game.players[banned]?.suspendedMatches == nil)
    }
}
