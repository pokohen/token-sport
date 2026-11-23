import SwiftUI
import TokenBaseballCore

struct PlayerDetail: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let player: Player

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(player.origin + (player.traits.isEmpty ? "" : " · " + player.traits.map(\.rawValue).joined(separator: ", "))).note()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), alignment: .leading, spacing: 2) {
                ForEach(Attributes.weights(for: player.position).map(\.0), id: \.self) { key in
                    Text("\(key.label(for: player.position.sport)) \(Int(player.attributes[key].rounded()))").font(.caption.monospacedDigit())
                }
            }
            if let line = player.football {
                if player.position == .goalkeeper {
                    Text("\(line.games)경기 · 무실점 \(line.cleanSheets)경기 · 선방 \(line.saves) · 실점 \(line.conceded) · 경고 \(line.yellowCards) · 퇴장 \(line.redCards)").note()
                } else {
                    Text("\(line.games)경기 · \(line.goals)골 \(line.assists)도움 · 슈팅 \(line.shots) (유효 \(line.shotsOnTarget)) · 경고 \(line.yellowCards) · 퇴장 \(line.redCards)").note()
                }
            } else if player.isPitcher {
                Text("\(player.pitching.games)경기 \(player.pitching.wins)승 \(player.pitching.losses)패 \(player.pitching.saves)세 · 평균자책점 \(String(format: "%.2f", player.pitching.era)) · \(player.pitching.innings)이닝 · 탈삼진 \(player.pitching.strikeouts) · \(player.pitching.pitches)구").note()
            } else {
                Text("\(player.batting.games)경기 타율 \(String(format: "%.3f", player.batting.average)) · \(player.batting.homeRuns)홈런 · \(player.batting.runsBattedIn)타점 · \(player.batting.steals)도루 · OPS \(String(format: "%.3f", player.batting.ops))").note()
            }
            let left = player.contract.seasonsLeft
            Text("계약 \(game.phase == .offseason ? (left <= 0 ? "만료 (오프시즌이 끝나면 떠남)" : "\(left)시즌 남음") : (left <= 1 ? "이번 시즌까지" : "\(left)시즌 남음"))\(player.contract.relegationClause ? " · 강등 조항 있음" : "")").note()

            if game.isExpiring(player) {
                let demand = game.renewalDemand(player)
                if let counter = game.counters.first(where: { $0.playerID == player.id }) {
                    Text("역제안: \(counter.years)시즌, 연봉 \(Format.money(counter.salary))").font(.caption.bold())
                    HStack {
                        Button("수락") { model.perform { try $0.acceptCounter(counter.id) } }
                        Button("거절") { model.perform { $0.declineCounter(counter.id) } }
                    }
                    .controlSize(.small)
                } else if game.proposals.contains(where: { $0.playerID == player.id }) {
                    Text("재계약 제안을 보냈습니다. 다음 경기 뒤에 답이 옵니다.").font(.caption.bold())
                } else {
                    Text("재계약 요구: \(demand.years)시즌, 연봉 \(Format.money(demand.salary))").font(.caption.bold())
                    HStack {
                        Button("요구대로 제안") {
                            model.perform { try $0.proposeRenewal(player.id, salary: demand.salary, years: demand.years) }
                        }
                        Button("10% 낮게 제안") {
                            model.perform { try $0.proposeRenewal(player.id, salary: demand.salary * 9 / 10, years: demand.years) }
                        }
                    }
                    .controlSize(.small)
                }
            }
            Button("방출", role: .destructive) { model.perform { try $0.release(player.id) } }
                .controlSize(.small)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.6), in: RoundedRectangle(cornerRadius: 8))
    }
}
