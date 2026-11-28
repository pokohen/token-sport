import Foundation
import TokenBaseballCore

// 경기 일정과 경기 시간 표시. Core의 규칙을 그대로 옮기고 문구만 번역한다.

extension Game {
    /// 다음 경기 이름: "7라운드", "컵대회 32강", "친선 경기 1/5", 플레이오프는 "승강 플레이오프 2차전".
    func localizedLabel(of next: NextMatch) -> String {
        switch next.kind {
        case .regular:
            return String(localized: "\(round + 1)라운드")
        case .cup:
            guard let cup else { return next.label }
            return String(localized: "컵대회 \(cup.localizedRoundName)")
        case .playoff:
            let mine = series.first { !$0.isDecided && ($0.upperTeam == userTeamID || $0.lowerTeam == userTeamID) }
            return mine?.localizedNextLabel ?? next.label
        case .friendly:
            return String(localized: "친선 경기 \(friendliesPlayed + 1)/\(Balance.friendliesPerOffseason)")
        }
    }
}

extension PlayoffSeries {
    var localizedNextLabel: String {
        switch kind {
        case .bestOfThree: String(localized: "승강 플레이오프 \(played + 1)차전")
        case .wildcard: String(localized: "승격 와일드카드 \(played + 1)차전")
        case .twoLegs: String(localized: "승격 플레이오프 준결승 \(played + 1)차전")
        case .single: String(localized: "승격 플레이오프 결승")
        }
    }
}

extension Cup {
    /// 라운드 이름: 쉬는 구단이 있는 첫 라운드는 "1라운드", 그 뒤로는 남은 구단 수로 부른다.
    static func localizedRoundName(ties: Int, first: Bool) -> String {
        if first, ties != 1 { return String(localized: "1라운드") }
        switch ties {
        case ...1: return String(localized: "결승")
        case 2: return String(localized: "준결승")
        default: return String(localized: "\(ties * 2)강")
        }
    }

    var localizedRoundName: String {
        isFinished ? String(localized: "결승") : Self.localizedRoundName(ties: ties.count, first: roundIndex == 0)
    }

    /// 그 구단이 지금까지 치른 경기 (라운드 이름과 함께). Core의 `path(of:)`와 같은 순서다.
    func localizedPath(of team: TeamID) -> [(round: String, tie: CupTie)] {
        var result: [(String, CupTie)] = []
        for (index, round) in history.enumerated() {
            if let tie = round.first(where: { $0.involves(team) }) {
                result.append((Self.localizedRoundName(ties: round.count, first: index == 0), tie))
            }
        }
        if !isFinished, let tie = ties.first(where: { $0.involves(team) && $0.isPlayed }) {
            result.append((localizedRoundName, tie))
        }
        return result
    }
}

extension MatchState {
    /// "3회말".
    var localizedInningLabel: String {
        isBottom ? String(localized: "\(inning)회말") : String(localized: "\(inning)회초")
    }
}

extension FootballMatch {
    /// 승부차기와 종료만 말로 쓴다. 나머지("67'", "45+2'")는 숫자라서 Core 것을 그대로 쓴다.
    var localizedClockLabel: String {
        switch period {
        case .shootout: String(localized: "승부차기")
        case .finished: String(localized: "종료")
        case .firstHalf, .secondHalf, .extraFirst, .extraSecond: clockLabel
        }
    }

    var localizedPeriodLabel: String {
        switch period {
        case .firstHalf: String(localized: "전반")
        case .secondHalf: String(localized: "후반")
        case .extraFirst: String(localized: "연장 전반")
        case .extraSecond: String(localized: "연장 후반")
        case .shootout: String(localized: "승부차기")
        case .finished: String(localized: "경기 종료")
        }
    }
}

extension BasketballMatch {
    /// "3Q 7:32", "연장 2:10", "종료".
    var localizedClockLabel: String {
        if isFinished { return String(localized: "종료") }
        let length = isOvertime ? Self.overtimeLength : Self.quarterLength
        let left = max(0, length - clock)
        let time = "\(left / 60):\(String(format: "%02d", left % 60))"
        return isOvertime ? String(localized: "연장 \(time)") : String(localized: "\(period)Q \(time)")
    }
}
