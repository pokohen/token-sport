import SwiftUI
import TokenBaseballCore

/// 축구 선발 11명과 벤치. 경기 전에 정한다.
struct FootballLineupView: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        if let lineup = game.currentFootballLineup {
            let custom = !game.userTeam.lineupOverride.isEmpty
            let ids = lineup.starters.map(\.id)
            let bench = lineup.bench.compactMap { game.players[$0] }
            Card(String(localized: "선발 11명 (\((game.userTeam.formation ?? .f442).label))"), trailing: custom ? String(localized: "직접 정함") : String(localized: "자동")) {
                ForEach(Array(lineup.starters.enumerated()), id: \.element.id) { index, entry in
                    if let player = game.players[entry.id] {
                        HStack(spacing: 6) {
                            PositionTag(position: entry.slot)
                                .foregroundStyle(entry.slot == player.position ? Color.primary : Theme.warn)
                            Text(player.name).font(.callout)
                            if player.isHot { Image(systemName: "flame.fill").foregroundStyle(Theme.loss).font(.caption2) }
                            Spacer()
                            Text("\(Int(player.ability.rounded()))").font(.callout.monospacedDigit())
                            Menu(String(localized: "교체", table: "Actions")) {
                                ForEach(bench) { sub in
                                    Button("\(sub.position.localizedLabel) \(sub.name) (\(Int(sub.ability.rounded())))") {
                                        var next = ids
                                        next[index] = sub.id
                                        model.perform { try $0.setLineup(next) }
                                    }
                                }
                            }
                            .fixedSize()
                            .disabled(bench.isEmpty)
                        }
                        .controlSize(.small)
                    }
                }
                if custom {
                    Button("자동 구성으로 되돌리기") { model.perform { try $0.setLineup([]) } }.controlSize(.small)
                }
                Text("주황색 자리는 제 포지션이 아니라 능력이 깎입니다. 골키퍼는 반드시 1명 들어가야 합니다. 포메이션은 경기 탭에서 바꿉니다.").note()
            }
            Card(String(localized: "벤치"), trailing: String(localized: "\(bench.count)명")) {
                if bench.isEmpty { Text("벤치에 선수가 없습니다.").note() }
                ForEach(bench) { player in
                    KeyValueRow(key: "\(player.position.localizedLabel) \(player.name)", value: "\(Int(player.ability.rounded()))")
                }
                Text("한 경기에 5명까지, 60분 이후 지친 선수부터 같은 포지션의 벤치 선수로 자동 교체됩니다.").note()
            }
        } else {
            Card { Text("골키퍼 1명을 포함해 11명이 있어야 선발을 짤 수 있습니다.").font(.callout) }
        }
    }
}
