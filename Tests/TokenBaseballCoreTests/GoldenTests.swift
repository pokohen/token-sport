import Foundation
import Testing
@testable import TokenBaseballCore

/// 야구 모드가 예전과 한 치도 다르지 않게 돌아가는지 지키는 검사.
/// 같은 시드로 한 시즌 반을 돌린 뒤의 상태를 지문으로 만들어, 기록해 둔 값과 비교한다.
/// 난수를 부르는 순서가 하나만 바뀌어도 지문이 달라진다.
///
/// 야구 동작을 일부러 바꿨다면 `TB_RECORD_GOLDEN=1 swift test --filter GoldenTests`로
/// 지문을 출력해 아래 값을 고친다. 저장 파일(fixture)은 예전 것을 그대로 둔다.
@Suite struct GoldenTests {
    static let fixture = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().appendingPathComponent("Fixtures/baseball-v2-save.json")

    static let midSeason = "f606a08f275e8bb3"
    static let nextSeason = "1605d87e82aae8e8"
    /// 예전 엔진으로 만들어 둔 저장 파일의 지문 (파일 내용이 그대로인지), 그리고 그 파일을 지금 코드로 이어 갔을 때의 지문.
    static let fixtureMidSeason = "6ef3c215f702e2fa"
    static let fixtureNextSeason = "286cbdf9812474d7"

    static func fingerprint(_ game: Game) -> String {
        var text = "\(game.rng.state)|\(game.season)|\(game.round)|\(game.phase)|\(game.funds.balance)|\(game.players.count)"
        for tier in LeagueTier.allCases {
            for row in game.standings[tier.index] {
                text += "|\(row.teamID):\(row.wins)-\(row.losses)-\(row.draws):\(row.runsFor)-\(row.runsAgainst)"
            }
        }
        for team in game.teams {
            text += "|\(team.id)\(team.tier.rawValue)\(team.roster.count)\(Int(team.fame * 100))\(team.funds)"
        }
        let ability = game.players.keys.sorted().reduce(0.0) { $0 + (game.players[$1]?.ability ?? 0) * Double($1 % 7 + 1) }
        text += "|\(Int(ability * 1000))"
        for item in game.news { text += "|\(item.text)" }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return String(hash, radix: 16)
    }

    /// 열 경기를 치르고 열한 번째 경기를 100구쯤 진행한 상태.
    static func midSeasonGame() throws -> (Game, AutoManager) {
        var game = TestGame.make(seed: 20_261_115)
        var manager = AutoManager(tokensPerMatch: 40_000_000)
        for _ in 0..<10 { try manager.playOne(&game) }
        manager.clock = manager.clock.addingTimeInterval(3600)
        try game.startMatch(now: manager.clock)
        for _ in 0..<100 { game.stepMatch() }
        return (game, manager)
    }

    /// 진행 중이던 경기를 끝내고 다음 시즌 3라운드까지.
    static func continueToNextSeason(_ game: inout Game, _ manager: inout AutoManager) throws {
        game.runMatchToEnd()
        while !(game.season == 2 && game.round == 3) {
            if game.isBankrupt {
                try game.foundNewClub(setup: .init(city: "대전", name: "대전 재창단"), now: manager.clock)
            }
            try manager.playOne(&game)
        }
    }

    @Test func 같은_시드면_예전과_똑같이_흘러간다() throws {
        var (game, manager) = try Self.midSeasonGame()
        if ProcessInfo.processInfo.environment["TB_RECORD_GOLDEN"] == "1" {
            // 저장 파일(fixture)은 다시 만들지 않는다. 예전에 만든 파일을 그대로 두어야
            // "예전 저장 파일을 지금 코드로 읽을 수 있는지"를 확인할 수 있다.
            print("GOLDEN midSeason \(Self.fingerprint(game))")
        }
        #expect(Self.fingerprint(game) == Self.midSeason)
        try Self.continueToNextSeason(&game, &manager)
        if ProcessInfo.processInfo.environment["TB_RECORD_GOLDEN"] == "1" {
            print("GOLDEN nextSeason \(Self.fingerprint(game))")
        }
        #expect(Self.fingerprint(game) == Self.nextSeason)
    }

    /// 종목을 나누기 전에 만든 저장 파일을 그대로 읽어 이어서 할 수 있어야 한다.
    @Test func 예전_저장_파일을_읽어_이어서_해도_똑같다() throws {
        let save = try JSONDecoder().decode(GameSave.self, from: Data(contentsOf: Self.fixture))
        var game = save.game
        #expect(game.live != nil)
        #expect(Self.fingerprint(game) == Self.fixtureMidSeason)
        // 자동 운영자의 시계와 토큰 번호를 저장 시점에 맞춘다.
        var manager = AutoManager(tokensPerMatch: 40_000_000)
        manager.clock = TestGame.start.addingTimeInterval(11 * 3600)
        manager.tokenID = 10
        try Self.continueToNextSeason(&game, &manager)
        if ProcessInfo.processInfo.environment["TB_RECORD_GOLDEN"] == "1" {
            print("GOLDEN fixtureNextSeason \(Self.fingerprint(game))")
        }
        #expect(Self.fingerprint(game) == Self.fixtureNextSeason)
    }
}
