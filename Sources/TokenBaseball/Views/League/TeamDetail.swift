import SwiftUI
import TokenBaseballCore

/// 순위표에서 팀을 눌렀을 때: 팀 정보와 선수단, 이적 제안.
struct TeamDetail: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let team: Team
    let row: StandingRow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("강도 \(Int(game.strength(of: team.id))) · 훈련소 Lv\(team.trainingLevel) · 경기장 Lv\(team.stadiumLevel)\(team.isUser ? "" : " · \(team.style.label(game.sport))")").note()
            if game.sport == .football {
                Text("득점 \(row.runsFor) · 실점 \(row.runsAgainst) · 골득실 \(row.goalDifference > 0 ? "+" : "")\(row.goalDifference) · 승점 \(row.points)").note()
            } else if game.sport == .basketball {
                let games = max(1, row.games)
                Text("평균 득점 \(String(format: "%.1f", Double(row.runsFor) / Double(games))) · 평균 실점 \(String(format: "%.1f", Double(row.runsAgainst) / Double(games)))").note()
            } else {
                Text("득점 \(row.runsFor) · 실점 \(row.runsAgainst) · 팀 타율 \(String(format: "%.3f", row.battingAverage)) · 팀 평균자책점 \(String(format: "%.2f", row.era))").note()
            }
            ForEach(game.roster(of: team.id).sorted { $0.ability > $1.ability }.prefix(8)) { player in
                PlayerLine(player: player, style: .compact) {
                    if !game.isCareer, !team.isUser, game.tradeWindowOpen {
                        let fee = game.value(for: player) * 13 / 10
                        Button("제안 \(Format.money(fee))") {
                            model.perform { try $0.proposeTransfer(player.id, fee: fee) }
                        }
                        .controlSize(.mini)
                        .disabled(game.proposals.contains { $0.playerID == player.id })
                    }
                }
            }
        }
        .padding(8)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
