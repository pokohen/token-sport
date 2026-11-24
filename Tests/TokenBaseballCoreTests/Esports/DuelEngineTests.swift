import Foundation
import Testing
@testable import TokenBaseballCore

/// 1:1 대전 엔진. 숫자의 목표는 docs/10-esports.md의 "엔진에서 맞춘 숫자".
@Suite struct DuelEngineTests {
    static let sets = 3000

    static func even(_ race: DuelRace = .human, _ value: Double = 60, _ style: DuelStyle = .balanced) -> DuelPlayer {
        DuelSample.player("가", race, .uniform(value), style)
    }

    @Test func 반드시_승부가_나고_기록이_맞아떨어진다() {
        var rng = SeededRNG(seed: 3)
        for index in 0..<300 {
            var set = DuelSet(first: Self.even(.alien), second: Self.even(.protector),
                              map: DuelMap.pool[index % 5], stakes: .regular, seed: rng.next())
            set.runToEnd()
            #expect(set.isFinished && set.winner != nil && set.ending != nil)
            #expect(set.tick <= DuelSet.maxSteps)
            for side in 0..<2 {
                let me = set.sides[side], them = set.sides[1 - side]
                #expect(me.army >= 0 && me.workers >= 0)
                #expect((1...set.map.maxBases).contains(me.bases))
                #expect(abs(me.armyKilled - them.armyLost) < 1e-6)
                #expect(abs(me.workersKilled - them.workersLost) < 1e-6)
            }
            #expect(set.log.last?.kind == .end)
            #expect(set.log.last?.text.contains("GG") == true)
        }
    }

    @Test func 같은_시드면_같은_세트이고_도중에_저장해도_그대로_이어진다() throws {
        let first = DuelSample.player("김하늘", .protector, DuelSample.typical(.protector, overall: 55), .gambit)
        let second = DuelSample.player("이수", .alien, DuelSample.typical(.alien, overall: 58), .rush)
        var a = DuelSet(first: first, second: second, map: DuelMap.pool[1], stakes: .ace, seed: 42)
        var b = a
        for _ in 0..<30 { a.step() }
        let data = try JSONEncoder().encode(a)
        var loaded = try JSONDecoder().decode(DuelSet.self, from: data)
        #expect(loaded == a)
        a.runToEnd()
        loaded.runToEnd()
        b.runToEnd()
        #expect(loaded == a)
        #expect(b == a)
    }

    @Test func 세트_길이는_1배속으로_3에서_5분() {
        let stats = DuelSample.run(Self.even(), Self.even(), sets: Self.sets)
        // 3초에 한 틱: 60~100틱이 3~5분.
        #expect((60...85).contains(stats.meanSteps), "평균 \(stats.meanSteps)틱")
        #expect(stats.maxSteps <= DuelSet.maxSteps)
        #expect(stats.share(stats.rushes) < 0.08, "초반에 끝난 세트 \(stats.share(stats.rushes))")
        #expect(stats.share(stats.timeouts) < 0.02)
        // 역전은 가끔 나온다.
        #expect((0.03...0.15).contains(stats.share(stats.comebacks)), "역전 \(stats.share(stats.comebacks))")
    }

    @Test func 자리에_따른_유불리가_없다() {
        let stats = DuelSample.run(Self.even(), Self.even(), sets: 4000)
        #expect((0.47...0.53).contains(stats.rate), "0번 자리 승률 \(stats.rate)")
        let alien = DuelSample.player("나", .alien, .uniform(60))
        let one = DuelSample.run(Self.even(), alien, sets: 3000, seed: 21).rate
        let other = DuelSample.run(alien, Self.even(), sets: 3000, seed: 21).rate
        #expect(abs(one - (1 - other)) < 0.04, "자리를 바꾸면 \(one) / \(1 - other)")
    }

    @Test(arguments: [(DuelRace.human, DuelRace.alien), (.alien, .protector), (.protector, .human)])
    func 같은_실력이면_종족전은_45에서_55퍼센트(pair: (DuelRace, DuelRace)) {
        let (a, b) = pair
        let flat = DuelSample.rate(Self.even(a), DuelSample.player("나", b, .uniform(60)), sets: Self.sets)
        let typical = DuelSample.rate(
            DuelSample.player("가", a, DuelSample.typical(a, overall: 60)),
            DuelSample.player("나", b, DuelSample.typical(b, overall: 60)), sets: Self.sets)
        #expect((0.45...0.55).contains(flat), "\(a.label) 대 \(b.label) 고른 능력 \(flat)")
        #expect((0.45...0.55).contains(typical), "\(a.label) 대 \(b.label) 종족형 능력 \(typical)")
        // 맵 하나만 보면 조금 더 기운다. 그래도 맵이 승부를 정하지는 않는다.
        for map in DuelMap.pool {
            let rate = DuelSample.rate(Self.even(a), DuelSample.player("나", b, .uniform(60)), sets: 1200, map: map)
            #expect((0.4...0.6).contains(rate), "\(map.name) \(rate)")
        }
    }

    @Test func 실력_차이가_승률을_가른다() {
        let rates = [3.0, 10, 20].map { gap in
            DuelSample.rate(Self.even(.human, 60 + gap), Self.even(.human, 60), sets: Self.sets)
        }
        #expect((0.54...0.64).contains(rates[0]), "+3: \(rates[0])")
        #expect((0.7...0.82).contains(rates[1]), "+10: \(rates[1])")
        #expect(rates[2] > 0.88 && rates[2] < 0.98, "+20: \(rates[2])")
        let low = DuelSample.rate(Self.even(.alien, 40), Self.even(.alien, 30), sets: Self.sets)
        #expect((0.7...0.85).contains(low), "능력 30대 +10: \(low)")
    }

    @Test func 능력치는_하나하나_승률을_올린다() {
        for (index, label) in DuelSkills.labels.enumerated() {
            var up = DuelSkills.uniform(60)
            up[keyPath: DuelSkills.keys[index]] = 70
            let rate = DuelSample.rate(DuelSample.player("가", .protector, up), Self.even(.protector), sets: Self.sets)
            #expect(rate > 0.52 && rate < 0.65, "\(label) +10: \(rate)")
        }
        // 멘탈은 큰 경기에서 더 크게 작용한다.
        var mental = DuelSkills.uniform(60)
        mental.mental = 75
        let player = DuelSample.player("가", .human, mental)
        let regular = DuelSample.rate(player, Self.even(), sets: 4000)
        let final = DuelSample.rate(player, Self.even(), sets: 4000, stakes: .final)
        #expect(final > regular + 0.02, "멘탈 +15: 보통 \(regular), 결승 \(final)")
    }

    @Test func 어떤_스타일도_압도하지_않는다() {
        for style in DuelStyle.allCases {
            for other in DuelStyle.allCases where other != style {
                let rate = DuelSample.rate(Self.even(.human, 60, style), Self.even(.human, 60, other), sets: 2000)
                #expect((0.43...0.57).contains(rate), "\(style.label) 대 \(other.label): \(rate)")
            }
        }
    }

    @Test func 빌드_상성은_양념이지_승부가_아니다() {
        var wins: [DuelBuild: (won: Int, played: Int)] = [:]
        var rng = SeededRNG(seed: 5)
        for index in 0..<8000 {
            var set = DuelSet(first: Self.even(), second: Self.even(), map: DuelMap.pool[index % 5], seed: rng.next())
            set.runToEnd()
            let mine = set.sides[0].build
            guard set.sides[1].build == mine.beats else { continue }
            var entry = wins[mine] ?? (0, 0)
            entry.played += 1
            if set.winner == 0 { entry.won += 1 }
            wins[mine] = entry
        }
        for build in DuelBuild.allCases {
            let entry = wins[build] ?? (0, 0)
            #expect(entry.played > 300)
            let rate = Double(entry.won) / Double(max(entry.played, 1))
            #expect((0.51...0.75).contains(rate), "\(build.label) 대 \(build.beats.label): \(rate)")
        }
    }

    @Test func 중계_문구는_지어낸_이름만_쓴다() {
        var set = DuelSet(first: Self.even(), second: DuelSample.player("나", .alien, .uniform(60), .gambit),
                          map: DuelMap.pool[0], seed: 9)
        var texts: [String] = []
        while !set.isFinished { texts += set.step().map(\.text) }
        let all = texts.joined(separator: "\n")
        #expect(all.contains("청동 협곡"))
        #expect(all.contains("GG"))
        #expect(!all.contains("이(가)"))
        #expect("김하늘".withSubject == "김하늘이" && "이수".withSubject == "이수가")
    }
}
