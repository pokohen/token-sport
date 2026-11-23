import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct CareerScoutTests {
    /// 윗 리그에서도 주전일 만큼 강한 유격수. 5부 구단 하나가 지켜보고 있다.
    func watched(interest: Double, seed: UInt64 = 71) throws -> (Game, TeamID) {
        var game = TestCareer.make(.shortstop, seed: seed)
        let id = try #require(game.career?.playerID)
        for (key, _) in Attributes.weights(for: .shortstop) { game.players[id]?.attributes[key] = 48 }
        game.players[id]?.potential = 90
        let upper = try #require(game.teams(in: .citizenSemiPro).first).id
        #expect(game.careerScoutEligible(upper))
        game.career?.scouts = [CareerScout(teamID: upper, interest: interest)]
        game.career?.matchesAtClub = Balance.careerOfferCooldown
        return (game, upper)
    }

    @Test func 평점이_좋으면_관심이_오르고_나쁘면_내린다() throws {
        var (game, team) = try watched(interest: 40)
        var career = try #require(game.career)
        let me = try #require(game.myPlayer)
        _ = game.updateCareerScouts(
            &career, me: me, performance: .init(rating: 8.0, line: ""), kind: .regular)
        let up = try #require(career.scouts?.first { $0.teamID == team })
        #expect(up.interest > 40 && up.lastChange > 0 && up.matchesWatched == 1)

        var bad = try #require(game.career)
        _ = game.updateCareerScouts(
            &bad, me: me, performance: .init(rating: 4.0, line: ""), kind: .regular)
        #expect((bad.scouts?.first { $0.teamID == team }?.interest ?? 0) < 40)

        // 내가 나오지 않은 경기는 관심도를 바꾸지 않는다.
        var idle = try #require(game.career)
        _ = game.updateCareerScouts(&idle, me: me, performance: nil, kind: .regular)
        #expect(idle.scouts?.first { $0.teamID == team }?.interest == 40)
    }

    @Test func 스카우트가_직접_온_경기는_두_배로_움직인다() throws {
        var (game, team) = try watched(interest: 40)
        let me = try #require(game.myPlayer)
        var plain = try #require(game.career)
        var copy = game
        _ = copy.updateCareerScouts(&plain, me: me, performance: .init(rating: 7.5, line: ""), kind: .regular)
        var visited = try #require(game.career)
        visited.scoutVisit = team
        let lines = game.updateCareerScouts(
            &visited, me: me, performance: .init(rating: 7.5, line: ""), kind: .regular)
        let a = try #require(plain.scouts?.first { $0.teamID == team }).lastChange
        let b = try #require(visited.scouts?.first { $0.teamID == team })
        #expect(abs(b.lastChange - a * Balance.careerScoutVisitMultiplier) < 0.001)
        #expect(b.visits == 1)
        #expect(lines.contains { $0.contains("스카우트가 경기를 지켜봤습니다") })
    }

    @Test func 관심이_문턱을_넘으면_이적_기간에_그_구단이_제안한다() throws {
        var (game, team) = try watched(interest: 69)
        #expect(game.tradeWindowOpen)
        game.resolveCareerMarketAfterMatch()
        #expect(game.career?.offers.isEmpty == true)

        game.career?.scouts?[0].interest = 85
        game.resolveCareerMarketAfterMatch()
        let offer = try #require(game.career?.offers.first)
        #expect(offer.kind == .transfer && offer.teamID == team)
        // 제안이 걸려 있는 동안은 또 보내지 않는다.
        game.career?.offers[0].matchesLeft = 3
        game.resolveCareerMarketAfterMatch()
        #expect(game.career?.offers.count == 1)

        // 이적 기간이 아니면 관심이 높아도 기다린다.
        var (closed, _) = try watched(interest: 95)
        closed.round = Balance.tradeDeadlineRound + 1
        #expect(!closed.tradeWindowOpen)
        closed.resolveCareerMarketAfterMatch()
        #expect(closed.career?.offers.isEmpty == true)
        #expect(closed.careerScouts.first?.interest == 95)
    }

    @Test func 이적을_요청하면_관심이_오르고_문턱이_낮아진다() throws {
        var (game, _) = try watched(interest: 45)
        #expect(game.careerScoutOfferThreshold == Balance.careerScoutOfferInterest)
        try game.requestCareerTransfer()
        #expect(game.careerScouts.first?.interest == 45 + Balance.careerScoutRequestBoost)
        #expect(game.careerScoutOfferThreshold == Balance.careerScoutOfferInterestRequested)
        game.resolveCareerMarketAfterMatch()
        #expect(game.career?.offers.count == 1)
    }

    @Test func 거절하거나_답하지_않으면_그_구단은_떠난다() throws {
        var (game, team) = try watched(interest: 90)
        game.resolveCareerMarketAfterMatch()
        let offer = try #require(game.career?.offers.first)
        try game.declineCareerOffer(offer.id)
        #expect(game.careerScouts.isEmpty)
        game.resolveCareerMarketAfterMatch()
        #expect(game.career?.offers.isEmpty == true)

        // 답하지 않고 한 경기가 지나도 떠난다.
        var (expiring, _) = try watched(interest: 90)
        expiring.resolveCareerMarketAfterMatch()
        #expect(expiring.career?.offers.count == 1)
        expiring.resolveCareerMarketAfterMatch()
        #expect(expiring.career?.offers.isEmpty == true)
        #expect(!expiring.careerScouts.contains { $0.teamID == team })
    }

    @Test func 구단을_옮기면_처음부터_다시_쌓는다() throws {
        var (game, team) = try watched(interest: 90)
        game.career?.scoutVisit = team
        game.resolveCareerMarketAfterMatch()
        let offer = try #require(game.career?.offers.first)
        try game.acceptCareerOffer(offer.id)
        #expect(game.userTeamID == team)
        #expect(game.careerScouts.isEmpty && game.careerScoutVisitor == nil)
    }

    @Test func 이미_주전이면_같은_리그_구단은_지켜보지_않는다() throws {
        var game = TestCareer.make(.shortstop, seed: 72)
        let id = try #require(game.career?.playerID)
        let same = try #require(game.teams(in: .citizenAmateur).first { $0.id != game.userTeamID }).id
        // 벤치 선수: 같은 리그에서 주전으로 쓸 구단은 지켜볼 수 있다.
        for (key, _) in Attributes.weights(for: .shortstop) { game.players[id]?.attributes[key] = 60 }
        #expect(game.careerRole(on: game.userTeamID) == .starter)
        #expect(!game.careerScoutEligible(same))
        #expect(!game.careerScoutEligible(game.userTeamID))
        // 두 리그 위(4부)까지는 지켜보고, 세 리그 위(3부)는 지켜보지 않는다.
        let twoUp = try #require(game.teams(in: .citizenPro).first { game.careerRole(on: $0.id) != .prospect }).id
        #expect(game.careerScoutEligible(twoUp))
        #expect(game.teams(in: .amateur).allSatisfy { !game.careerScoutEligible($0.id) })
        #expect(game.teams(in: .pro).allSatisfy { !game.careerScoutEligible($0.id) })
        // 계약이 끝났으면 주전이어도 같은 리그 구단이 데려갈 수 있다.
        game.players[id]?.contract.seasonsLeft = 0
        #expect(game.careerScoutEligible(same))
        #expect(game.careerScoutOfferThreshold == Balance.careerScoutOfferInterestExpired)
    }

    @Test func 두_리그를_뛰어오르려면_유망주가_아니라_주전을_다툴_실력이어야_한다() throws {
        var game = TestCareer.make(.shortstop, seed: 75)
        let id = try #require(game.career?.playerID)
        game.career?.fame = 100
        // 5부에서는 유망주로 볼 만하지만 4부에서는 한참 모자란 능력.
        let level = Balance.abilityRange(.citizenSemiPro).lowerBound - 4
        for (key, _) in Attributes.weights(for: .shortstop) { game.players[id]?.attributes[key] = level }
        let oneUp = game.teams(in: .citizenSemiPro).filter { game.careerRole(on: $0.id) == .prospect }
        let twoUp = game.teams(in: .citizenPro).filter { game.careerRole(on: $0.id) == .prospect }
        try #require(!oneUp.isEmpty && !twoUp.isEmpty)
        #expect(oneUp.allSatisfy { game.careerScoutEligible($0.id) })
        #expect(twoUp.allSatisfy { !game.careerScoutEligible($0.id) })
        // 이름이 알려지지 않았으면 바로 위 리그도 유망주로 보지 않는다.
        game.career?.fame = 0
        #expect(oneUp.allSatisfy { !game.careerScoutEligible($0.id) })
    }

    @Test func 윗_리그일수록_훈련_한_번에_더_많이_오르고_더_비싸다() throws {
        var game = TestCareer.make(.shortstop, seed: 76)
        TestGame.addTokens(&game, 500_000_000, id: "a", at: TestGame.hours(1))
        let id = try #require(game.career?.playerID)
        game.players[id]?.potential = 99
        var steps: [Double] = [], costs: [Int] = []
        for tier in LeagueTier.allCases.reversed() {
            game.teams[game.userTeamID].tier = tier
            #expect(game.careerTrainingStep == Balance.careerTrainingStep(tier))
            let before = try #require(game.myPlayer).ability
            var copy = game
            costs.append(copy.careerTrainingCost(.contact))
            try copy.trainCareer(.contact, critical: false)
            steps.append(try #require(copy.myPlayer).ability - before)
            #expect(abs(steps.last! - Balance.careerTrainingStep(tier)) < 0.0001)
        }
        #expect(zip(steps, steps.dropFirst()).allSatisfy { $0 < $1 })
        #expect(zip(costs, costs.dropFirst()).allSatisfy { $0 < $1 })
        // 능력 1을 올리는 값도 윗 리그가 더 비싸다.
        #expect(Double(costs.last!) / steps.last! > Double(costs.first!) / steps.first!)
        // 한계까지 조금 남았으면 남은 만큼만 오른다.
        let ability = try #require(game.myPlayer).ability
        game.players[id]?.potential = ability + 0.05
        try game.trainCareer(.contact, critical: false)
        #expect(abs(try #require(game.myPlayer).ability - (ability + 0.05)) < 0.0001)
        #expect(throws: GameError.self) { try game.trainCareer(.contact, critical: false) }
    }

    @Test func 자리가_다_차면_주전으로_쓸_구단이_관심_낮은_구단을_밀어낸다() throws {
        var game = TestCareer.make(.shortstop, seed: 74)
        let id = try #require(game.career?.playerID)
        // 5부의 약한 구단에서는 주전, 강한 구단에서는 주전 경쟁쯤 되는 능력으로 맞춘다.
        let upper = game.teams(in: .citizenSemiPro)
        func bar(_ team: Team) -> Double {
            game.roster(of: team.id).filter { $0.position == .shortstop }.map(\.ability).max() ?? 0
        }
        let sorted = upper.sorted { bar($0) < bar($1) }
        let level = (bar(sorted[2]) + bar(sorted[3])) / 2
        for (key, _) in Attributes.weights(for: .shortstop) { game.players[id]?.attributes[key] = level }
        game.players[id]?.potential = 90
        game.career?.fame = 100
        let notStarter = sorted.filter { game.careerRole(on: $0.id) != .starter && game.careerScoutEligible($0.id) }
        try #require(notStarter.count >= 3)
        #expect(sorted.contains { game.careerRole(on: $0.id) == .starter })
        game.career?.scouts = notStarter.prefix(3).enumerated().map { index, team in
            CareerScout(teamID: team.id, interest: Double(30 + index * 10))
        }
        game.career?.fame = 100
        let me = try #require(game.myPlayer)
        var replaced = false
        for _ in 0..<40 where !replaced {
            var career = try #require(game.career)
            let lines = game.updateCareerScouts(
                &career, me: me, performance: .init(rating: 6.2, line: ""), kind: .regular)
            #expect((career.scouts?.count ?? 0) <= Balance.careerScoutMax)
            if lines.contains(where: { $0.contains("밀려 떠났습니다") }) {
                replaced = true
                #expect(career.scouts?.contains { game.careerRole(on: $0.teamID) == .starter } == true)
                // 밀려난 것은 관심이 가장 낮던 구단이다.
                #expect(career.scouts?.contains { $0.teamID == notStarter[0].id } == false)
            }
        }
        #expect(replaced)
    }

    @Test func 한_시즌을_돌리면_스카우트가_오가고_저장해도_그대로다() throws {
        var game = TestCareer.make(.center, seed: 73)
        var auto = CareerAuto()
        auto.acceptsTransfers = false
        var arrived = false, visited = false
        while game.season == 1, game.phase == .regular {
            try auto.playOne(&game)
            if !game.careerScouts.isEmpty { arrived = true }
            if game.careerScoutVisitor != nil { visited = true }
            #expect(game.careerScouts.count <= Balance.careerScoutMax)
            #expect(game.careerScouts.allSatisfy { (0...100).contains($0.interest) && $0.teamID != game.userTeamID })
        }
        #expect(arrived && visited)
        #expect(game.news.contains { $0.text.contains("스카우트") } || game.lastResult?.summary.contains { $0.contains("스카우트") } == true)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("scout-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try SaveStore(fileURL: url).save(GameSave(game: game))
        #expect(try SaveStore(fileURL: url).load()?.game == game)
    }
}
