import Foundation
import Testing
@testable import TokenBaseballCore

/// e스포츠 1:1 대전의 세계: 종족, 능력치, 팀, 로스터, 리그 이름, 나이 (→ docs/10-esports.md 만드는 순서 3).
@Suite struct DuelWorldTests {
    static func make(_ race: Position = .protector, seed: UInt64 = 1) -> Game {
        TestCareer.make(race, seed: seed)
    }

    @Test func 종족이_포지션_자리에_들어간다() {
        #expect(Position.all(for: .duel) == [.human, .alien, .protector])
        #expect(Position.duel.map(\.race) == [.human, .alien, .protector])
        #expect(Position.shortstop.race == nil)
        #expect(Attributes.Key.all(for: .duel) == [.control, .macro, .strategy, .judgment, .mental])
        #expect(Attributes.Key.all(for: .duel).map { $0.label(for: .duel) } == DuelSkills.labels)
        // 능력(CA)은 엔진의 종족 비중으로 낸다.
        for position in Position.duel {
            let sum = Attributes.weights(for: position).reduce(0) { $0 + $1.1 }
            #expect(abs(sum - 1) < 1e-9)
        }
    }

    @Test func 선수의_능력치로_세트에_나간다() throws {
        let game = Self.make(.alien)
        let me = try #require(game.myPlayer)
        let duel = DuelPlayer(me)
        #expect(duel.race == .alien)
        #expect(duel.name == me.name)
        #expect(abs(duel.overall - me.ability) < 1e-9)
        #expect(duel.skills.macro == me.attributes.macro)
        #expect(duel.skills.control == me.attributes.control)
    }

    @Test func 여섯_리그_열_팀에_세_종족이_섞인_여섯_명() {
        let game = Self.make()
        #expect(game.sport == .duel)
        var names = Set<String>()
        for tier in LeagueTier.allCases {
            let teams = game.teams(in: tier)
            #expect(teams.count == 10)
            for team in teams {
                names.insert(team.name)
                let roster = game.roster(of: team.id)
                #expect(roster.count >= 6)
                for race in Position.duel {
                    #expect(roster.filter { $0.position == race }.count >= 2, "\(team.name) \(race)")
                }
                #expect(roster.allSatisfy { $0.position.sport == .duel })
                #expect(game.canField(team))
            }
        }
        // 팀 이름이 겹치지 않는다.
        #expect(names.count == 60)
    }

    @Test func 이름과_나이가_e스포츠답다() {
        let game = Self.make(seed: 3)
        let everyone = game.players.values.filter { $0.id != game.career?.playerID }
        #expect(everyone.allSatisfy { !NameGenerator.blockedEsports.contains($0.name) })
        #expect(game.teams.allSatisfy { team in NameGenerator.esportsAvoided.allSatisfy { !team.name.contains($0) } })
        #expect(everyone.allSatisfy { (16...31).contains($0.age) })
        // 내 선수는 16세에 시작한다.
        #expect(game.myPlayer?.age == 16)
        #expect(game.teams(in: .pro).allSatisfy { $0.name.hasSuffix("게이밍") })
        #expect(game.teams(in: .citizenAmateur).allSatisfy { $0.name.contains("PC방") })
        #expect(LeagueTier.citizenAmateur.displayName(for: .duel) == "6부 PC방 리그")
        #expect(LeagueTier.pro.displayName(for: .duel) == "1부 프로 리그")
        #expect(LeagueTier.pro.displayName(for: .baseball) == LeagueTier.pro.displayName)
    }

    @Test func 나이가_들수록_훈련_효과가_서서히_준다() {
        let factors = (16...35).map(Balance.duelAgeFactor)
        #expect(zip(factors, factors.dropFirst()).allSatisfy { $0 >= $1 })
        #expect(Balance.duelAgeFactor(17) == 1.6)
        #expect(Balance.duelAgeFactor(24) == 0.8)
        #expect(Balance.duelAgeFactor(33) > 0)
        #expect(Balance.ageGrowthFactor(17, position: .human) == 1.6)
    }

    @Test func e스포츠_능력치는_다른_종목의_저장_파일에_쓰지_않는다() throws {
        var baseball = Attributes()
        baseball.contact = 50
        let plain = String(decoding: try JSONEncoder().encode(baseball), as: UTF8.self)
        #expect(!plain.contains("macro"))
        #expect(!plain.contains("mental"))

        var duel = Attributes()
        duel.macro = 61.5
        duel.mental = 40
        let data = try JSONEncoder().encode(duel)
        #expect(String(decoding: data, as: UTF8.self).contains("macro"))
        #expect(try JSONDecoder().decode(Attributes.self, from: data) == duel)
    }

    @Test func 화면_없이_팀_경기를_치른다() throws {
        let game = Self.make(seed: 5)
        let teams = game.teams(in: .pro)
        var results: [String] = []
        for index in 0..<8 {
            let score = try #require(game.quietDuelMatch(home: teams[index].id, away: teams[index + 1].id, seed: UInt64(index)))
            #expect(max(score.home, score.away) == 2)
            #expect(min(score.home, score.away) <= 1)
            results.append("\(score.home):\(score.away)")
        }
        // 같은 시드면 같은 결과.
        let again = try #require(game.quietDuelMatch(home: teams[0].id, away: teams[1].id, seed: 0))
        #expect("\(again.home):\(again.away)" == results[0])
        // 플레이오프는 5전 3선승.
        let long = try #require(game.quietDuelMatch(home: teams[0].id, away: teams[1].id, bestOf: 5, seed: 9))
        #expect(max(long.home, long.away) == 3)
    }

    @Test func 저장_칸은_따로_있다() {
        #expect(SaveSlot.career(for: .duel) == .duelPlayer)
        #expect(SaveSlot.duelPlayer.rawValue == "esports-duel")
    }
}

extension DuelWorldTests {
    @Test func 나이가_들면_손은_떨어지고_운영과_판단은_오른다() {
        var game = Self.make(seed: 7)
        var player = game.players.values.first { $0.position == .human && $0.id != game.career?.playerID }!
        player.age = 31
        let before = player.attributes
        game.ageDuelPlayer(&player)
        #expect(player.attributes.control < before.control)
        #expect(player.attributes.macro >= before.macro)
        #expect(player.attributes.judgment >= before.judgment)
        #expect(player.attributes.strategy == before.strategy)

        var young = player
        young.age = 21
        young.attributes = before
        game.ageDuelPlayer(&young)
        #expect(young.attributes == before)
    }
}

extension DuelWorldTests {
    @Test func 서른다섯_시즌을_마치면_반드시_은퇴한다() {
        var game = Self.make(seed: 11)
        let me = game.career!.playerID
        let veterans = game.players.values.filter { $0.id != me }.prefix(20).map(\.id)
        for id in veterans { game.players[id]?.age = Balance.duelRetirementAge }
        game.startOffseason()
        #expect(veterans.allSatisfy { game.players[$0]?.teamID == nil || game.players[$0] == nil })
    }
}
