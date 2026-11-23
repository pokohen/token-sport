import Foundation
import Testing
@testable import TokenBaseballCore

@Suite struct FormatTests {
    @Test func 능력치_이름은_종목에_맞춘다() {
        #expect(Attributes.Key.speed.label(for: .baseball) == "주력")
        #expect(Attributes.Key.speed.label(for: .football) == "스피드")
        #expect(Attributes.Key.speed.label(for: .basketball) == "스피드")
        #expect(Attributes.Key.shooting.label(for: .football) == "슈팅")
        #expect(Attributes.Key.shooting.label(for: .basketball) == "슛")
        // 선수 만들기와 훈련 탭이 같은 이름을 쓰도록, 종목의 모든 능력치에 이름이 있다.
        for sport in Sport.allCases {
            for key in Attributes.Key.all(for: sport) { #expect(!key.label(for: sport).isEmpty) }
        }
    }

    @Test func 자금은_줄여서_표시한다() {
        #expect(Format.money(320_000_000) == "₩3.2억")
        #expect(Format.money(85_000_000) == "₩8,500만")
        #expect(Format.money(100_000) == "₩10만")
        #expect(Format.money(9_999) == "₩9,999")
        #expect(Format.money(-1_500_000) == "−₩150만")
        #expect(Format.money(12_345_678_901) == "₩123억")
    }

    @Test func 토큰과_시간() {
        #expect(Format.tokens(120_500_000) == "120.5M")
        #expect(Format.tokens(950_200) == "950.2K")
        #expect(Format.tokens(999_949) == "999.9K")
        #expect(Format.tokens(999_950) == "1.0M")
        #expect(Format.tokens(999_999) == "1.0M")
        #expect(Format.tokens(1_000) == "1.0K")
        #expect(Format.tokens(999) == "999")
        #expect(Format.countdown(23 * 60) == "23분")
        #expect(Format.countdown(22 * 60 + 1) == "23분")
        #expect(Format.countdown(3600) == "1시간")
        #expect(Format.countdown(65 * 60) == "1시간 5분")
        #expect(Format.countdown(20) == "1분 미만")
    }

    @Test func 상단바는_설정한_숫자_하나를_보여주고_경기_상황은_늘_보여준다() throws {
        var game = TestGame.make()
        let now = TestGame.start
        #expect(game.menuBarText(now: now, todayTokens: 120_500_000) == "₩10만 •")
        game.settings.menuBarDisplay = .today
        #expect(game.menuBarText(now: now, todayTokens: 120_500_000) == "120.5M •")
        game.settings.menuBarDisplay = .nextMatch
        #expect(game.menuBarText(now: now, todayTokens: 0) == "경기 가능")

        try game.startMatch(now: now)
        #expect(game.menuBarText(now: now, todayTokens: 0) == "⚾ 0:0 1회초")
        game.runMatchToEnd()
        // 경기가 끝나면 설정과 상관없이 "경기 종료"를 표시하고, 확인할 때까지 남는다.
        let ended = game.menuBarText(now: now, todayTokens: 0)
        #expect(ended.hasPrefix("⚾ 경기 종료 "))
        #expect(ended.contains(try #require(game.lastResult).label))
        game.acknowledgeResult()
        #expect(game.menuBarText(now: now.addingTimeInterval(37 * 60), todayTokens: 0) == "경기까지 23분")
        #expect(game.menuBarTooltip(now: now, todayTokens: 5_000).contains("오늘 사용량 5.0K"))
    }
}
