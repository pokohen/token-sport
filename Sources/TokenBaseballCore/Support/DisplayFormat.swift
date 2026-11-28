import Foundation

// 화면에 보일 돈, 남은 시간, 팬 수. `Format`과 같은 규칙(기준, 반올림)으로 만들고 단위만 번역한다.
// 한국어 단위(만·억, 시간·분)를 열쇠로 쓴다. 다른 언어의 단위는 앱의 번역 표에서 정한다.
// 맥의 언어에 따라 글이 달라지므로 저장되는 글(소식, 경기 기록)에는 쓰지 않는다. 그런 글은 `Format`을 쓴다.

public enum DisplayFormat {
    /// 한국어·일본어는 만·억(1만 = 10⁴)으로 끊고, 영어는 K·M·B(10³)로 끊는다. 단위가 달라 번역 표만으로는 못 바꾼다.
    public static var usesMyriad: Bool { Bundle.main.preferredLocalizations.first.map { $0 != "en" } ?? true }

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
    public static func money(_ amount: Int) -> String {
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
    public static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return String(localized: "1분 미만") }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return String(localized: "\(minutes)분") }
        return minutes % 60 == 0
            ? String(localized: "\(minutes / 60)시간") : String(localized: "\(minutes / 60)시간 \(minutes % 60)분")
    }

    /// "3.2만 명", "1,240명", "1,000만 명" (영어는 단위 없이 `32K`, 앞뒤 문구가 "fans"를 붙인다).
    public static func fans(_ fans: Int) -> String {
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
    public func localizedFundsText(_ amount: Int) -> String {
        isCareer ? "\(Format.tokens(amount)) P" : DisplayFormat.money(amount)
    }
}
