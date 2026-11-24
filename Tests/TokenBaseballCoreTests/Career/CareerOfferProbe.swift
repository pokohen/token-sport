import Foundation
import Testing
@testable import TokenBaseballCore

/// 이적 제안이 얼마나 자주 오고 선수가 얼마나 빨리 올라가는지 재는 도구.
/// 평소에는 돌지 않는다: `TB_PROBE=1 swift test --filter CareerOfferProbe`
@Suite(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] != nil))
struct CareerOfferProbe {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] != "pace"))
    func 세_시즌_동안의_제안과_승격() throws {
        var out = ""
        // `TB_PROBE=low`면 토큰을 적게 쓰는 경우만 본다.
        let all: [(Position, Int)] = [(.shortstop, 5_000_000), (.starter, 5_000_000), (.forward, 5_000_000), (.smallForward, 5_000_000), (.smallForward, 500_000)]
        let cases = ProcessInfo.processInfo.environment["TB_PROBE"] == "low" ? [(.smallForward, 500_000), (.starter, 5_000_000)] : all
        for (position, tokens) in cases {
            for seed in [51, 52] as [UInt64] {
                var game = TestCareer.make(position, seed: seed)
                var auto = CareerAuto()
                auto.tokensPerMatch = tokens
                var offers = 0, moves = 0, seen: Set<Int> = [], guardCount = 0
                var lastTeam = game.userTeamID
                // 세 자리가 다 찼는데 문턱에 닿은 곳이 없는 경기 수, 문턱을 넘었는데 제안이 못 나간 경기 수.
                var clogged = 0, blocked = 0, starterGames = 0
                while game.season <= 3, guardCount < 260 {
                    guardCount += 1
                    guard game.nextMatch() != nil || game.career?.isFreeAgent == true else { break }
                    for offer in game.career?.offers ?? [] where offer.kind == .transfer && !seen.contains(offer.id) {
                        seen.insert(offer.id)
                        offers += 1
                    }
                    if game.career?.isFreeAgent == true { auto.manage(&game); continue }
                    try auto.playOne(&game)
                    let threshold = game.careerScoutOfferThreshold
                    let scouts = game.careerScouts
                    if scouts.count >= Balance.careerScoutMax, !scouts.contains(where: { $0.interest >= threshold }) { clogged += 1 }
                    if scouts.contains(where: { $0.interest >= threshold }), game.career?.offers.isEmpty == true { blocked += 1 }
                    if game.careerRole(on: game.userTeamID) == .starter { starterGames += 1 }
                    if game.userTeamID != lastTeam { moves += 1; lastTeam = game.userTeamID }
                }
                let c = game.career!
                let path = c.history.map { "\($0.tier.rawValue)부" }.joined(separator: "→")
                out += "\n\(position.rawValue) \(tokens / 1_000_000)M s\(seed): 제안 \(offers) 이적 \(moves) 리그 \(game.userTier.rawValue)부 능력 \(Int(game.myPlayer?.ability ?? 0)) 신뢰 \(Int(c.trust)) 명성 \(Int(c.fame)) 스카우트 \(scoutText(game)) 막힘 \(clogged) 대기 \(blocked) 주전 \(starterGames)/\(guardCount) 시즌별 \(path)"
            }
        }
        print("OFFERPROBE\(out)")
    }

    /// 성장 속도의 아래와 위: 훈련을 전혀 하지 않을 때(경기만)와 포인트가 넘쳐 매번 다섯 번을 다 할 때.
    /// `TB_PROBE=pace swift test --filter CareerOfferProbe`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] == "pace"))
    func 경기만_뛸_때와_훈련을_다_할_때의_성장() throws {
        var out = ""
        for position in [Position.shortstop, .forward, .smallForward] {
            for tokens in [0, 400_000_000] {
                var game = TestCareer.make(position, seed: 61)
                game.players[game.career!.playerID]?.potential = 90
                var auto = CareerAuto()
                auto.tokensPerMatch = tokens
                var guardCount = 0
                var rows: [String] = ["\(Int(game.myPlayer!.ability))"]
                var season = 1
                while game.season <= 8, guardCount < 700 {
                    guardCount += 1
                    guard game.nextMatch() != nil || game.career?.isFreeAgent == true else { break }
                    if game.career?.isFreeAgent == true { auto.manage(&game); continue }
                    try auto.playOne(&game)
                    if game.season != season {
                        season = game.season
                        rows.append("\(Int(game.myPlayer?.ability ?? 0))/\(game.userTier.rawValue)부")
                    }
                }
                out += "\n\(position.rawValue) \(tokens == 0 ? "경기만" : "훈련 전부"): " + rows.joined(separator: " → ")
            }
        }
        print("PACEPROBE\(out)")
    }

    /// 리그 수준을 훌쩍 넘는 선수(모든 능력치 `level`)가 6부에서 한 시즌 동안 얼마나 압도하는지.
    /// 같은 포지션의 리그 평균 선수와 나란히 찍는다. `TB_PROBE=star swift test --filter CareerOfferProbe`
    @Test(.enabled(if: ProcessInfo.processInfo.environment["TB_PROBE"] == "star"))
    func 능력이_압도적인_선수의_활약() throws {
        // `TB_LEVELS=28,48,62,76,90` 능력 수준들, `TB_SEEDS=2` 수준마다 돌릴 횟수(평균을 낸다),
        // `TB_SHAPE=spike`면 포지션에서 가장 중요한 능력치만 그 수준이고 나머지는 25 낮다.
        let env = ProcessInfo.processInfo.environment
        let levels = (env["TB_LEVELS"] ?? "90").split(separator: ",").compactMap { Double($0) }
        let seeds = Int(env["TB_SEEDS"] ?? "1") ?? 1
        let spike = env["TB_SHAPE"] == "spike"
        var out = ""
        func f(_ v: Double) -> String { String(format: "%.2f", v) }
        // `TB_POSITIONS=GK,SG`처럼 일부 포지션만 볼 수 있다.
        let only = env["TB_POSITIONS"].map { Set($0.split(separator: ",").map(String.init)) }
        let positions = [Position.forward, .midfielder, .goalkeeper, .shortstop, .starter] + Position.basketball
        for position in positions where only?.contains(position.rawValue) ?? true {
            out += "\n\(position.rawValue):"
            for level in levels {
                var rating = 0.0, a = 0.0, b = 0.0, c = 0.0
                for seed in 0..<seeds {
                    var game = TestCareer.make(position, seed: UInt64(81 + seed))
                    let id = game.career!.playerID
                    let main = Attributes.weights(for: position).max { $0.1 < $1.1 }?.0
                    for key in Attributes.Key.all(for: position.sport) {
                        game.players[id]?.attributes[key] = spike && key != main ? level - 25 : level
                    }
                    game.players[id]?.potential = 99
                    game.career?.trust = 90
                    var clock = TestGame.start
                    while game.season == 1, game.phase == .regular, game.nextMatch() != nil {
                        clock = clock.addingTimeInterval(3600)
                        try game.startMatch(now: clock)
                        game.runMatchToEnd()
                    }
                    let me = game.players[id]!
                    let career = game.career!
                    rating += (career.history.last?.averageRating ?? career.seasonAverageRating) ?? 0
                    switch position {
                    case .goalkeeper:
                        let l = career.history.last?.football ?? me.football ?? FootballLine()
                        a += Double(l.cleanSheets); b += Double(l.saves) / Double(max(1, l.games)); c += Double(l.conceded) / Double(max(1, l.games))
                    case .forward, .midfielder:
                        let l = career.history.last?.football ?? me.football ?? FootballLine()
                        let g = Double(max(1, l.games))
                        a += Double(l.goals) / g; b += Double(l.assists) / g; c += Double(l.shots) / g
                    case .pointGuard, .shootingGuard, .smallForward, .powerForward, .center5:
                        let l = career.history.last?.basketball ?? me.basketball ?? BasketballLine()
                        a += l.pointsPerGame; b += l.reboundsPerGame; c += l.assistsPerGame
                    case .starter:
                        let l = career.history.last?.pitching ?? me.pitching
                        a += l.era; b += Double(l.wins); c += Double(l.strikeouts)
                    default:
                        let l = career.history.last?.batting ?? me.batting
                        a += l.average; b += Double(l.homeRuns); c += l.ops
                    }
                }
                let n = Double(seeds)
                out += "  [\(Int(level)): 평점 \(f(rating / n)) · \(f(a / n)) / \(f(b / n)) / \(f(c / n))]"
            }
        }
        print("STARPROBE (FW·MF: 경기당 골/도움/슈팅, GK: 무실점 경기/경기당 선방/경기당 실점, SS: 타율/홈런/OPS, SP: 평균자책점/승/탈삼진, 농구 PG·SG·SF·PF·CE: 경기당 득점/리바운드/어시스트)\(out)")
    }

    func scoutText(_ game: Game) -> String {
        game.careerScouts.map { "\(Int($0.interest))" }.joined(separator: "/")
    }
}
