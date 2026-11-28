import Foundation
import Testing
@testable import TokenBaseballCore

/// e스포츠 선수 모드의 숫자를 한눈에 본다: `TB_PROBE=duelcareer swift test --filter DuelCareerProbe`.
@Suite struct DuelCareerProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] == "duelcareer"))
    func 시즌마다_능력_리그_팬_평점() throws {
        var out = ""
        for (position, seed) in [(Position.human, UInt64(91)), (.alien, 92), (.protector, 93)] {
            for tokens in [0, 400_000_000] {
                var game = TestCareer.make(position, seed: seed)
                game.players[game.career!.playerID]?.potential = 90
                var auto = CareerAuto()
                auto.tokensPerMatch = tokens
                var rows: [String] = []
                var season = 1
                var guardCount = 0
                while game.season <= 8, guardCount < 900, game.career?.retired == false {
                    guardCount += 1
                    guard game.nextMatch() != nil || game.career?.isFreeAgent == true else { break }
                    if game.career?.isFreeAgent == true { auto.manage(&game); continue }
                    try auto.playOne(&game)
                    if game.season != season, let last = game.career?.history.last {
                        season = game.season
                        let line = last.duel ?? DuelLine()
                        rows.append("\(last.age)세 \(last.tier.rawValue)부 능력\(Int(game.myPlayer?.ability ?? 0)) 평점\(String(format: "%.2f", last.averageRating ?? 0)) 세트\(line.setWins)-\(line.setLosses) 팬\(fansText(game.career?.fans ?? 0))")
                    }
                }
                out += "\n\(position.label) \(tokens == 0 ? "경기만" : "훈련 전부"):\n  " + rows.joined(separator: "\n  ")
            }
        }
        print("DUELCAREER\(out)")
    }
}
