import SwiftUI
import TokenBaseballCore

/// e스포츠: 개인 대회 여섯 단계와 내가 나간 대회. 리그 탭의 컵대회 자리에 나온다.
struct DuelCircuitCard: View {
    let game: Game
    let career: Career

    var body: some View {
        let fans = career.fans ?? 0
        Card(String(localized: "개인 대회"), trailing: game.duelTitle.map { String(localized: "칭호: \($0)") }) {
            Text("팀 리그와 상관없이 팬 수로 나갑니다. 바로 아래 대회에서 우승하면 팬이 모자라도 다음 대회 한 번은 초대받습니다.").note()
            ForEach(DuelTournament.allCases.reversed(), id: \.self) { tournament in
                let wins = (career.duelWins ?? []).indices.contains(tournament.rawValue - 1) ? career.duelWins![tournament.rawValue - 1] : 0
                let open = game.canEnterDuel(tournament)
                KeyValueRow(
                    key: String(localized: "\(tournament.rawValue)단계 \(tournament.baseName)"),
                    value: (open ? String(localized: "출전 가능") : String(localized: "팬 \(fansText(tournament.requiredFans))")) + (wins > 0 ? String(localized: " · 우승 \(wins)회") : ""),
                    valueColor: open ? Theme.win : .secondary)
            }
            KeyValueRow(key: String(localized: "지금 팬"), value: fansText(fans))
            let recent = (career.duelEvents ?? []).suffix(5).reversed()
            if !recent.isEmpty {
                Divider()
                ForEach(Array(recent.enumerated()), id: \.offset) { _, event in
                    KeyValueRow(
                        key: String(localized: "\(event.season)시즌 \(event.name)"), value: event.finish,
                        valueColor: event.won ? Theme.win : .primary)
                }
            }
        }
        .font(.callout)
    }
}
