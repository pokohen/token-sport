import Foundation
import TokenBaseballCore

// 돈, 남은 시간, 팬 수, 상단바 글자. Core의 `Format`과 같은 규칙(기준, 반올림)으로 만들고 단위만 번역한다.
// 한국어 단위(만·억, 시간·분)를 열쇠로 쓴다. 다른 언어의 단위는 표에서 정한다.

enum DisplayFormat {
    /// 한국어·일본어는 만·억(1만 = 10⁴)으로 끊고, 영어는 K·M·B(10³)로 끊는다. 단위가 달라 번역 표만으로는 못 바꾼다.
    static var usesMyriad: Bool { Bundle.main.preferredLocalizations.first.map { $0 != "en" } ?? true }

    /// 영어식 줄임: `320M`, `85M`, `500K`, `2.5B`. 소수는 버려서 한 자리까지 (한국어의 3.2억처럼).
    private static func western(_ value: Int) -> String {
        func short(_ unit: Double) -> String {
            let number = Double(value) / unit
            if number >= 100 { return Int(number).formatted() }
            let text = String(format: "%.1f", (number * 10).rounded(.down) / 10)
            return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
        }
        if value >= 1_000_000_000 { return short(1_000_000_000) + "B" }
        if value >= 1_000_000 { return short(1_000_000) + "M" }
        if value >= 10_000 { return short(1_000) + "K" }
        return value.formatted()
    }

    /// 자금을 줄여서: `₩3.2억`, `₩8,500만`, `₩12,345` (영어는 `₩320M`, `₩85M`).
    static func money(_ amount: Int) -> String {
        let sign = amount < 0 ? "−" : ""
        let value = abs(amount)
        if !usesMyriad { return "\(sign)₩\(western(value))" }
        if value >= 100_000_000 {
            let eok = Double(value) / 100_000_000
            let text = eok >= 100 ? Int(eok).formatted() : String(format: "%.1f", (eok * 10).rounded(.down) / 10)
            return String(localized: "\(sign)₩\(text)억")
        }
        if value >= 10_000 {
            return String(localized: "\(sign)₩\((value / 10_000).formatted())만")
        }
        return "\(sign)₩\(value.formatted())"
    }

    /// 남은 시간을 말로: `23분`, `1시간 5분`, `1시간`. 1분이 안 남았으면 `1분 미만`.
    static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return String(localized: "1분 미만") }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return String(localized: "\(minutes)분") }
        return minutes % 60 == 0
            ? String(localized: "\(minutes / 60)시간") : String(localized: "\(minutes / 60)시간 \(minutes % 60)분")
    }

    /// "3.2만 명", "1,240명", "1,000만 명" (영어는 단위 없이 `32K`, 앞뒤 문구가 "fans"를 붙인다).
    static func fans(_ fans: Int) -> String {
        if !usesMyriad { return western(fans) }
        switch fans {
        case ..<10_000: return String(localized: "\(fans.formatted())명")
        case ..<100_000_000:
            let man = Double(fans) / 10_000
            let text = man < 100 ? String(format: "%.1f", man).replacingOccurrences(of: ".0", with: "") : Int(man).formatted()
            return String(localized: "\(text)만 명")
        default:
            return String(localized: "\(String(format: "%.1f", Double(fans) / 100_000_000))억 명")
        }
    }
}

extension Game {
    /// 이 칸의 돈 단위로: 선수 모드는 훈련 포인트(`1.2M P`), 구단 모드는 자금(`₩120만`).
    func localizedFundsText(_ amount: Int) -> String {
        isCareer ? "\(Format.tokens(amount)) P" : DisplayFormat.money(amount)
    }

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
