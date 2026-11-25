import Foundation
import Testing
@testable import TokenBaseballCore

/// 종목마다 같은 시드로 한 시즌 반을 돌린 뒤의 상태를 지문으로 남긴다.
/// 야구 구단은 `GoldenTests`가 지키고, 여기서는 축구 구단과 선수 모드 여섯 가지(야구 타자·투수, 축구 공격수·골키퍼, 농구, e스포츠)를 지킨다.
/// 종목 분기를 정리하는 것처럼 "동작은 그대로"여야 하는 변경 뒤에 지문이 하나라도 달라지면 동작이 바뀐 것이다.
///
/// 동작을 일부러 바꿨다면 `TB_RECORD_GOLDEN=1 swift test --filter SportFingerprintTests`로 지문을 출력해 아래 값을 고친다.
@Suite struct SportFingerprintTests {
    static let expected: [String: String] = [
        "football-club": "5c8db5a061496a73",
        "career-SS": "b13e2a6725af28ff",
        "career-SP": "113593d1485b42a2",
        "career-FW": "b4316833e76fec35",
        "career-GK": "5162157a27709435",
        "career-SG": "5f37a5c57527848f",
        "career-PT": "b9bf6cb540d288dc",
    ]

    /// 모든 선수, 구단, 순위, 소식, 커리어를 정해진 순서로 이어 붙여 해시한다.
    /// 딕셔너리는 순서가 실행마다 달라지므로 열쇠로 정렬해서 하나씩 넣는다.
    static func fingerprint(_ game: Game) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        var data = Data("\(game.rng.state)|\(game.season)|\(game.round)|\(game.phase)|\(game.funds.balance)".utf8)
        for id in game.players.keys.sorted() {
            data.append(try encoder.encode(game.players[id]))
        }
        data.append(try encoder.encode(game.teams))
        data.append(try encoder.encode(game.standings))
        for item in game.news { data.append(Data(item.text.utf8)) }
        if let career = game.career {
            data.append(Data("|\(career.playerID)|\(career.fame)|\(career.trust)|\(career.history.count)|\(career.clubs)".utf8))
            data.append(try encoder.encode(career.history))
            data.append(Data("|\(career.offers.map { "\($0.teamID)\($0.kind)" })".utf8))
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in data { hash = (hash ^ UInt64(byte)) &* 0x100_0000_01b3 }
        return String(hash, radix: 16)
    }

    static func check(_ key: String, _ game: Game) throws {
        let print_ = try fingerprint(game)
        if ProcessInfo.processInfo.environment["TB_RECORD_GOLDEN"] == "1" { print("GOLDEN \(key) \(print_)") }
        #expect(print_ == expected[key], "\(key)")
    }

    @Test func 축구_구단() throws {
        var game = Game.newGame(
            setup: .init(city: "수원", name: "수원 테스트 FC"), now: TestGame.start, seed: 20_261_124, sport: .football)
        var manager = AutoManager(tokensPerMatch: 40_000_000)
        while !(game.season == 2 && game.round == 10) {
            if game.isBankrupt {
                try game.foundNewClub(setup: .init(city: "수원", name: "수원 재창단"), now: manager.clock)
            }
            try manager.playOne(&game)
        }
        try Self.check("football-club", game)
    }

    @Test(arguments: [Position.shortstop, .starter, .forward, .goalkeeper, .shootingGuard, .protector])
    func 선수_모드(_ position: Position) throws {
        var game = TestCareer.make(position, seed: 20_261_124)
        var auto = CareerAuto()
        auto.tokensPerMatch = 20_000_000
        // 한 시즌을 다 치르고(오프시즌, 이적 제안 포함) 다음 시즌 10라운드까지.
        while !(game.season == 2 && game.round == 10) {
            try auto.playOne(&game)
        }
        try Self.check("career-\(position.rawValue)", game)
    }
}
