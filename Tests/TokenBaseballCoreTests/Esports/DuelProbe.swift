import Foundation
import Testing
@testable import TokenBaseballCore

/// 1:1 대전 엔진의 숫자를 한눈에 본다. `TB_PROBE=duel swift test --filter DuelProbe`
@Suite struct DuelProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] == "duel"))
    func 숫자_보기() {
        let n = 4000
        func p(_ s: String) { print("DUELPROBE \(s)") }
        func pct(_ x: Double) -> String { String(format: "%.1f%%", x * 100) }

        let even = DuelSample.player("가", .human, .uniform(60))
        let base = DuelSample.run(even, DuelSample.player("나", .human, .uniform(60)), sets: n)
        p("길이: 평균 \(String(format: "%.0f", base.meanSteps))틱 (\(String(format: "%.1f", base.meanMinutes))분), 10%=\(base.percentile(0.1)) 50%=\(base.percentile(0.5)) 90%=\(base.percentile(0.9)) 최대=\(base.maxSteps)")
        p("끝: 초반 \(pct(base.share(base.rushes))) · 시간 \(pct(base.share(base.timeouts))) · 역전 \(pct(base.share(base.comebacks))) · 0번 승률 \(pct(base.rate))")

        for (a, b) in [(DuelRace.human, DuelRace.alien), (.alien, .protector), (.protector, .human)] {
            let flat = DuelSample.rate(DuelSample.player("가", a, .uniform(60)), DuelSample.player("나", b, .uniform(60)), sets: n)
            let typical = DuelSample.rate(
                DuelSample.player("가", a, DuelSample.typical(a, overall: 60)),
                DuelSample.player("나", b, DuelSample.typical(b, overall: 60)), sets: n)
            var maps: [String] = []
            for map in DuelMap.pool {
                let r = DuelSample.rate(DuelSample.player("가", a, .uniform(60)), DuelSample.player("나", b, .uniform(60)), sets: 1200, map: map)
                maps.append("\(map.name) \(pct(r))")
            }
            p("\(a.label) 대 \(b.label): 고른 능력 \(pct(flat)) · 종족형 능력 \(pct(typical)) · \(maps.joined(separator: ", "))")
        }

        for gap in [3.0, 5, 10, 20] {
            let r = DuelSample.rate(DuelSample.player("가", .human, .uniform(60 + gap)), DuelSample.player("나", .human, .uniform(60)), sets: n)
            let low = DuelSample.rate(DuelSample.player("가", .alien, .uniform(30 + gap)), DuelSample.player("나", .alien, .uniform(30)), sets: n)
            p("능력 +\(Int(gap)): 60대 \(pct(r)) · 30대 \(pct(low))")
        }

        for (index, label) in DuelSkills.labels.enumerated() {
            var up = DuelSkills.uniform(60)
            up[keyPath: DuelSkills.keys[index]] = 70
            let r = DuelSample.rate(DuelSample.player("가", .protector, up), DuelSample.player("나", .protector, .uniform(60)), sets: n)
            let ace = DuelSample.rate(DuelSample.player("가", .protector, up), DuelSample.player("나", .protector, .uniform(60)), sets: n, stakes: .final)
            p("\(label) +10: \(pct(r)) · 결승 \(pct(ace))")
        }

        for style in DuelStyle.allCases {
            var row: [String] = []
            for other in DuelStyle.allCases {
                let r = DuelSample.rate(DuelSample.player("가", .human, .uniform(60), style), DuelSample.player("나", .human, .uniform(60), other), sets: 2000)
                row.append("\(other.label) \(pct(r))")
            }
            p("\(style.label) 대: \(row.joined(separator: " · "))")
        }

        for style in DuelStyle.allCases {
            let r = DuelSample.rate(DuelSample.player("가", .human, .uniform(52), style), DuelSample.player("나", .human, .uniform(60)), sets: n)
            p("약한 쪽(52 대 60)이 \(style.label)일 때 이변 \(pct(r))")
        }

        // 빌드 상성: 첫 틱만 돌려 빌드를 보고, 빌드 조합마다 승률을 센다.
        var wins: [String: (Int, Int)] = [:]
        var rng = SeededRNG(seed: 5)
        for index in 0..<n * 2 {
            var set = DuelSet(first: DuelSample.player("가", .human, .uniform(60)), second: DuelSample.player("나", .human, .uniform(60)),
                              map: DuelMap.pool[index % 5], seed: rng.next())
            set.runToEnd()
            let key = "\(set.sides[0].build.label) 대 \(set.sides[1].build.label)"
            var entry = wins[key] ?? (0, 0)
            entry.1 += 1
            if set.winner == 0 { entry.0 += 1 }
            wins[key] = entry
        }
        for build in DuelBuild.allCases {
            let key = "\(build.label) 대 \(build.beats.label)"
            let (w, t) = wins[key] ?? (0, 1)
            p("빌드 \(key): \(pct(Double(w) / Double(t))) (\(t)세트)")
        }
    }
}
