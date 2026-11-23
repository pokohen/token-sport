import Foundation

public enum Format {
    /// 자금을 줄여서: `₩3.2억`, `₩8,500만`, `₩12,345`.
    public static func money(_ amount: Int) -> String {
        let sign = amount < 0 ? "−" : ""
        let value = abs(amount)
        if value >= 100_000_000 {
            let eok = Double(value) / 100_000_000
            let text = eok >= 100 ? Int(eok).formatted() : String(format: "%.1f", (eok * 10).rounded(.down) / 10)
            return "\(sign)₩\(text)억"
        }
        if value >= 10_000 {
            return "\(sign)₩\((value / 10_000).formatted())만"
        }
        return "\(sign)₩\(value.formatted())"
    }

    /// 토큰 수: `120.5M`, `950.2K`, `812`.
    public static func tokens(_ count: Int) -> String {
        // 반올림해서 1000.0K가 되는 수는 M으로 넘긴다.
        if count >= 999_950 { return String(format: "%.1fM", Double(count) / 1_000_000) }
        if count >= 1_000 { return String(format: "%.1fK", Double(count) / 1_000) }
        return "\(count)"
    }

    /// 남은 시간을 말로: `23분`, `1시간 5분`, `1시간`. 1분이 안 남았으면 `1분 미만`.
    public static func countdown(_ seconds: TimeInterval) -> String {
        guard seconds >= 60 else { return "1분 미만" }
        let minutes = Int((seconds / 60).rounded(.up))
        if minutes < 60 { return "\(minutes)분" }
        return minutes % 60 == 0 ? "\(minutes / 60)시간" : "\(minutes / 60)시간 \(minutes % 60)분"
    }
}

extension Game {
    /// 이 칸의 돈 단위로: 선수 모드는 훈련 포인트(`1.2M P`), 구단 모드는 자금(`₩120만`).
    public func fundsText(_ amount: Int) -> String {
        isCareer ? "\(Format.tokens(amount)) P" : Format.money(amount)
    }

    /// 값을 낼 수 없으면 그 이유. 낼 수 있으면 nil.
    func insufficientFundsReason(_ cost: Int) -> String? {
        guard funds.balance < cost else { return nil }
        return isCareer
            ? "훈련 포인트가 모자랍니다. \(fundsText(cost))가 필요합니다."
            : "자금이 모자랍니다. \(fundsText(cost))이 필요합니다."
    }

    /// 로그에서 읽은 사용량을 자금에 반영한다. 번 금액을 돌려준다.
    @discardableResult
    public mutating func collect(_ records: [UsageRecord], now: Date) -> Int {
        guard !isBankrupt else { return 0 }
        let earned = funds.collect(records, now: now)
        refreshFinancialState()
        return earned
    }

    /// 상단바에 띄울 글자. 경기 상황은 설정과 상관없이 보여준다.
    public func menuBarText(now: Date, todayTokens: Int) -> String {
        if isBankrupt { return "구단 해체" }
        if let live {
            let mine = live.userIsHome ? live.state.home.runs : live.state.away.runs
            let theirs = live.userIsHome ? live.state.away.runs : live.state.home.runs
            return "⚾ \(mine):\(theirs) \(live.state.inningLabel)"
        }
        if let liveFootball, let score = liveScore {
            return "⚽ \(score.mine):\(score.theirs) \(liveFootball.state.clockLabel)"
        }
        if let liveBasketball, let score = liveScore {
            return "🏀 \(score.mine):\(score.theirs) \(liveBasketball.state.clockLabel)"
        }
        if let lastResult, !lastResult.acknowledged {
            return "\(sport.symbol) 경기 종료 \(lastResult.label)"
        }
        let ready = charges > 0 && nextMatch() != nil
        switch settings.menuBarDisplay {
        case .funds:
            return fundsText(funds.balance) + (ready ? " •" : "")
        case .today:
            return Format.tokens(todayTokens) + (ready ? " •" : "")
        case .nextMatch:
            if ready { return "경기 가능" }
            guard nextMatch() != nil, let wait = timeToNextCharge(now: now) else { return "—" }
            return "경기까지 " + Format.countdown(wait)
        }
    }

    /// 상단바 툴팁: 자금, 오늘 사용량, 다음 경기를 모두 보여준다.
    public func menuBarTooltip(now: Date, todayTokens: Int) -> String {
        var lines = [
            isCareer ? "훈련 포인트 \(Format.tokens(funds.balance)) P" : "구단 자금 \(Format.money(funds.balance))",
            "오늘 사용량 \(Format.tokens(todayTokens))",
        ]
        let marks = chargeMarks
        if let wait = timeToNextCharge(now: now) {
            lines.append("경기 기회 \(marks) (다음 기회까지 \(Format.countdown(wait)))")
        } else {
            lines.append("경기 기회 \(marks)")
        }
        if let career {
            if career.retired { lines.append("은퇴했습니다. 새 선수를 만들 수 있습니다") }
            if career.isFreeAgent { lines.append("무소속: 입단할 구단을 골라 주세요") }
            if !career.offers.isEmpty, !career.isFreeAgent { lines.append("답할 계약 제안 \(career.offers.count)건") }
            return lines.joined(separator: "\n")
        }
        switch financialState {
        case .warning: lines.append("재정 경고: 자금이 다음 5경기 연봉보다 적습니다")
        case .crisis(let left): lines.append("재정 위기: 유예 \(left)경기")
        default: break
        }
        return lines.joined(separator: "\n")
    }

    /// 남은 경기 기회 표시 (예: ⚾⚾○).
    public var chargeMarks: String {
        String(repeating: sport.symbol, count: charges)
            + String(repeating: "○", count: Balance.maxMatchCharges - charges)
    }

    /// 진행 중인 내 경기의 점수.
    public var liveScore: (mine: Int, theirs: Int)? {
        if let live {
            return live.userIsHome
                ? (live.state.home.runs, live.state.away.runs) : (live.state.away.runs, live.state.home.runs)
        }
        if let liveFootball {
            return liveFootball.userIsHome
                ? (liveFootball.state.home.goals, liveFootball.state.away.goals)
                : (liveFootball.state.away.goals, liveFootball.state.home.goals)
        }
        if let liveBasketball {
            return liveBasketball.userIsHome
                ? (liveBasketball.state.home.points, liveBasketball.state.away.points)
                : (liveBasketball.state.away.points, liveBasketball.state.home.points)
        }
        return nil
    }

    /// 다른 종목의 구단을 운영하다가 이 구단으로 돌아왔다.
    /// 쉬는 동안 쓴 토큰과 흐른 시간은 세지 않는다.
    public mutating func resume(now: Date) {
        funds.skip(to: now)
        chargeAnchor = now
    }

    /// 팝오버를 열어 경기 결과를 확인했다.
    public mutating func acknowledgeResult() {
        lastResult?.acknowledged = true
    }
}
