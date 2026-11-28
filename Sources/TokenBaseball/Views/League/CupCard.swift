import SwiftUI
import TokenBaseballCore

/// 리그 탭: 컵대회. 내 구단이 걸어온 길과 지금 라운드의 대진을 보여 준다.
struct CupCard: View {
    let game: Game
    let cup: Cup

    private var mine: TeamID { game.userTeamID }

    var body: some View {
        Card(String(localized: "컵대회"), trailing: trailing) {
            Text(status).font(.callout.weight(.medium))
                .foregroundStyle(cup.champion == mine ? Theme.win : .primary)
            let path = cup.path(of: mine)
            if !path.isEmpty {
                Divider()
                ForEach(Array(path.enumerated()), id: \.offset) { _, step in
                    row(round: step.round, tie: step.tie, highlightMine: true)
                }
            }
            if !cup.isFinished, cup.ties.count <= 8 {
                Divider()
                Text("\(cup.roundName) 대진").note()
                ForEach(Array(cup.ties.enumerated()), id: \.offset) { _, tie in
                    row(round: nil, tie: tie, highlightMine: false)
                }
            } else if cup.isFinished, let final = cup.history.last?.first {
                Divider()
                row(round: String(localized: "결승"), tie: final, highlightMine: false)
            }
            Text("여섯 리그 \(game.teams.count)개 구단이 모두 나오는 단판 승부입니다. 매 라운드 다시 추첨하고, 아랫 리그 구단이 홈에서 치릅니다. 비기면 끝날 때까지 갑니다\(game.sport == .football ? String(localized: " (연장, 승부차기)") : String(localized: " (연장)")). 이기면 명성이 오르고, 윗 리그 구단을 잡으면 더 많이 오릅니다. 리그 순위와 시즌 기록에는 들어가지 않습니다.")
                .note().fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private var trailing: String {
        if cup.isFinished { return String(localized: "\(cup.season)시즌 끝") }
        if cup.isDue { return String(localized: "\(cup.roundName) 진행 중") }
        if let round = game.nextCupLeagueRound { return String(localized: "\(cup.roundName) · 리그 \(round)라운드 뒤") }
        return cup.roundName
    }

    private var status: String {
        if let champion = cup.champion {
            return champion == mine ? String(localized: "우승했습니다!") : String(localized: "우승: \(game.teams[champion].name) (\(game.teams[champion].tier.rawValue)부)")
        }
        if cup.byes.contains(mine) { return String(localized: "1라운드는 쉽니다 (부전승).") }
        if let tie = cup.ties.first(where: { $0.involves(mine) }) {
            if tie.winner == nil {
                let opponent = game.teams[tie.opponent(of: mine)]
                return String(localized: "\(cup.roundName): \(tie.home == mine ? String(localized: "홈") : String(localized: "원정")) vs \(opponent.name) (\(opponent.tier.rawValue)부)")
            }
            return tie.winner == mine ? String(localized: "\(cup.roundName)을(를) 통과했습니다.") : String(localized: "\(cup.roundName)에서 탈락했습니다.")
        }
        if let last = cup.path(of: mine).last { return String(localized: "\(last.round)에서 탈락했습니다.") }
        return String(localized: "이번 대회에는 나서지 못했습니다.")
    }

    private func row(round: String?, tie: CupTie, highlightMine: Bool) -> some View {
        let home = game.teams[tie.home], away = game.teams[tie.away]
        return HStack(spacing: 6) {
            if let round { Text(round).note().frame(width: 52, alignment: .leading) }
            Text("\(home.name) (\(home.tier.rawValue)부)")
                .fontWeight(tie.winner == tie.home ? .semibold : .regular).lineLimit(1)
            Spacer(minLength: 4)
            Text(score(tie)).monospacedDigit()
                .foregroundStyle(highlightMine && tie.isPlayed ? (tie.winner == mine ? Theme.win : Theme.loss) : .primary)
            Spacer(minLength: 4)
            Text("\(away.name) (\(away.tier.rawValue)부)")
                .fontWeight(tie.winner == tie.away ? .semibold : .regular).lineLimit(1)
        }
        .font(.caption)
    }

    private func score(_ tie: CupTie) -> String {
        guard let home = tie.homeScore, let away = tie.awayScore else { return tie.isPlayed ? String(localized: "부전승") : "vs" }
        return "\(home) : \(away)" + (tie.shootout ? String(localized: " (승부차기)") : "")
    }
}
