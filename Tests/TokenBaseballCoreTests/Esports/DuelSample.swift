import Foundation
@testable import TokenBaseballCore

/// 1:1 대전 엔진을 여러 세트 돌려 숫자를 모은다.
enum DuelSample {
    static func player(_ name: String, _ race: DuelRace, _ skills: DuelSkills, _ style: DuelStyle = .balanced) -> DuelPlayer {
        DuelPlayer(name: name, race: race, skills: skills, style: style)
    }

    /// 종합 능력이 `overall`이 되도록, 종족이 중요하게 보는 능력치를 `tilt`만큼 높이고 나머지를 낮춘 선수.
    static func typical(_ race: DuelRace, overall: Double, tilt: Double = 8) -> DuelSkills {
        var skills = DuelSkills.uniform(0)
        for key in DuelSkills.keys {
            skills[keyPath: key] = overall + (race.weights[keyPath: key] - 0.2) / 0.1 * tilt
        }
        let shift = overall - skills.overall(race)
        for key in DuelSkills.keys { skills[keyPath: key] += shift }
        return skills
    }

    struct Stats {
        var sets = 0, firstWins = 0, steps = 0, maxSteps = 0, rushes = 0, timeouts = 0, comebacks = 0
        var stepList: [Int] = []
        var rate: Double { Double(firstWins) / Double(max(sets, 1)) }
        var meanSteps: Double { Double(steps) / Double(max(sets, 1)) }
        func share(_ count: Int) -> Double { Double(count) / Double(max(sets, 1)) }
        /// 1배속(3초에 한 틱) 기준 평균 분.
        var meanMinutes: Double { meanSteps * 3 / 60 }
        func percentile(_ p: Double) -> Int {
            let sorted = stepList.sorted()
            return sorted.isEmpty ? 0 : sorted[min(sorted.count - 1, Int(Double(sorted.count) * p))]
        }
    }

    /// 두 선수를 `sets`번 붙인다. 맵은 맵 풀을 돌려 쓴다 (`map`을 주면 그 맵만).
    static func run(
        _ first: DuelPlayer, _ second: DuelPlayer, sets: Int, map: DuelMap? = nil,
        stakes: DuelStakes = .regular, seed: UInt64 = 11
    ) -> Stats {
        var rng = SeededRNG(seed: seed)
        var stats = Stats()
        for index in 0..<sets {
            let chosen = map ?? DuelMap.pool[index % DuelMap.pool.count]
            var set = DuelSet(first: first, second: second, map: chosen, stakes: stakes, seed: rng.next())
            set.runToEnd()
            stats.sets += 1
            if set.winner == 0 { stats.firstWins += 1 }
            stats.steps += set.tick
            stats.stepList.append(set.tick)
            stats.maxSteps = max(stats.maxSteps, set.tick)
            if set.ending == .rush { stats.rushes += 1 }
            if set.ending == .timeout { stats.timeouts += 1 }
            if set.isComeback { stats.comebacks += 1 }
        }
        return stats
    }

    /// 자리를 바꿔 두 번 붙여, 자리 효과를 지운 `first`의 승률.
    static func rate(_ first: DuelPlayer, _ second: DuelPlayer, sets: Int, map: DuelMap? = nil,
                     stakes: DuelStakes = .regular, seed: UInt64 = 11) -> Double {
        let a = run(first, second, sets: sets / 2, map: map, stakes: stakes, seed: seed)
        let b = run(second, first, sets: sets / 2, map: map, stakes: stakes, seed: seed &+ 1)
        return Double(a.firstWins + (b.sets - b.firstWins)) / Double(a.sets + b.sets)
    }
}
