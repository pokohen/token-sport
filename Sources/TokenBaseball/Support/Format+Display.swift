import Foundation
import TokenBaseballCore

// 상단바 글자. Core의 `menuBarText`와 같은 규칙으로 만들고 말만 번역한다. 돈·시간·팬 수는 Core의 `DisplayFormat`.

extension Game {

    /// 상단바에 띄울 글자. Core의 `menuBarText`와 같은 순서로 고른다. 경기 상황은 설정과 상관없이 보여준다.
    func localizedMenuBarText(now: Date, todayTokens: Int) -> String {
        if isBankrupt { return String(localized: "구단 해체") }
        if let live, let score = liveScore {
            return "⚾ \(score.mine):\(score.theirs) \(live.state.localizedInningLabel)"
        }
        if let liveFootball, let score = liveScore {
            return "⚽ \(score.mine):\(score.theirs) \(liveFootball.state.localizedClockLabel)"
        }
        if let liveBasketball, let score = liveScore {
            return "🏀 \(score.mine):\(score.theirs) \(liveBasketball.state.localizedClockLabel)"
        }
        if let liveDuel, let score = liveScore {
            let clock = liveDuel.state.current.map { " " + String(localized: "\(liveDuel.state.records.count + 1)세트 \($0.clockLabel)") } ?? ""
            return "🎮 \(score.mine):\(score.theirs)\(clock)"
        }
        if let lastResult, !lastResult.acknowledged {
            return String(localized: "\(sport.symbol) 경기 종료 \(lastResult.localizedLabel)")
        }
        let ready = charges > 0 && nextMatch() != nil
        switch settings.menuBarDisplay {
        case .funds:
            return localizedFundsText(funds.balance) + (ready ? " •" : "")
        case .today:
            return Format.tokens(todayTokens) + (ready ? " •" : "")
        case .nextMatch:
            if ready { return String(localized: "경기 가능") }
            guard nextMatch() != nil, let wait = timeToNextCharge(now: now) else { return "—" }
            return String(localized: "경기까지 \(DisplayFormat.countdown(wait))")
        }
    }

    /// 상단바 툴팁: 자금, 오늘 사용량, 다음 경기를 모두 보여준다.
    func localizedMenuBarTooltip(now: Date, todayTokens: Int) -> String {
        var lines = [
            isCareer
                ? String(localized: "훈련 포인트 \(Format.tokens(funds.balance)) P") : String(localized: "구단 자금 \(DisplayFormat.money(funds.balance))"),
            String(localized: "오늘 사용량 \(Format.tokens(todayTokens))"),
        ]
        let marks = chargeMarks
        if let wait = timeToNextCharge(now: now) {
            lines.append(String(localized: "경기 기회 \(marks) (다음 기회까지 \(DisplayFormat.countdown(wait)))"))
        } else {
            lines.append(String(localized: "경기 기회 \(marks)"))
        }
        if let career {
            if career.retired { lines.append(String(localized: "은퇴했습니다. 새 선수를 만들 수 있습니다")) }
            if career.isFreeAgent { lines.append(String(localized: "무소속: 입단할 구단을 골라 주세요")) }
            if !career.offers.isEmpty, !career.isFreeAgent { lines.append(String(localized: "답할 계약 제안 \(career.offers.count)건")) }
            return lines.joined(separator: "\n")
        }
        switch financialState {
        case .warning: lines.append(String(localized: "재정 경고: 자금이 다음 5경기 연봉보다 적습니다"))
        case .crisis(let left): lines.append(String(localized: "재정 위기: 유예 \(left)경기"))
        case .healthy, .bankrupt: break
        }
        return lines.joined(separator: "\n")
    }
}
