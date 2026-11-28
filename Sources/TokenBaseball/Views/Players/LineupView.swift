import SwiftUI
import TokenBaseballCore

/// 라인업과 선발 투수. 경기 전에 정한다.
struct LineupView: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        if game.sport == .football {
            FootballLineupView(game: game)
        } else {
            baseball
        }
    }

    @ViewBuilder private var baseball: some View {
        if let lineup = game.currentLineup {
            let custom = !game.userTeam.lineupOverride.isEmpty
            Card(String(localized: "타순"), trailing: custom ? String(localized: "직접 정함") : String(localized: "자동")) {
                let ids = lineup.batters.map(\.id)
                let bench = game.roster(of: game.userTeamID).filter { !$0.isPitcher && !ids.contains($0.id) }
                ForEach(Array(lineup.batters.enumerated()), id: \.element.id) { index, entry in
                    if let player = game.players[entry.id] {
                        HStack(spacing: 6) {
                            Text("\(index + 1)").font(.callout.monospacedDigit()).frame(width: 14)
                            PositionTag(position: entry.position)
                                .foregroundStyle(entry.position == player.position || entry.position == .designated ? Color.primary : Theme.warn)
                            Text(player.name).font(.callout)
                            Spacer()
                            Text("\(Int(player.ability.rounded()))").font(.callout.monospacedDigit())
                            Button { move(ids, from: index, to: index - 1) } label: { Image(systemName: "chevron.up") }
                                .disabled(index == 0)
                            Button { move(ids, from: index, to: index + 1) } label: { Image(systemName: "chevron.down") }
                                .disabled(index == ids.count - 1)
                            Menu(String(localized: "교체", table: "Actions")) {
                                ForEach(bench) { sub in
                                    Button("\(sub.position.label) \(sub.name) (\(Int(sub.ability.rounded())))") {
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
                Text("주황색 자리는 제 포지션이 아니라 수비가 깎입니다.").note()
            }
            Card(String(localized: "투수")) {
                let pitchers = game.roster(of: game.userTeamID).filter(\.isPitcher)
                Picker("다음 경기 선발", selection: Binding(
                    get: { game.userTeam.starterOverride },
                    set: { value in model.perform { try $0.setNextStarter(value) } })
                ) {
                    Text("자동 (\(game.players[lineup.starter]?.name ?? ""))").tag(PlayerID?.none)
                    ForEach(pitchers) { Text("\($0.position.label) \($0.name)").tag(PlayerID?.some($0.id)) }
                }
                .font(.callout)
                ForEach(lineup.bullpen, id: \.self) { id in
                    if let player = game.players[id] {
                        KeyValueRow(key: "\(player.position.label) \(player.name)", value: "\(Int(player.ability.rounded()))")
                    }
                }
                Text("선발 투수는 등판 후 \(Balance.starterRest(game.userTier))경기를 쉬어야 다시 선발로 나옵니다.").note()
            }
        } else {
            Card { Text("야수 9명과 투수 1명 이상이 있어야 라인업을 짤 수 있습니다.").font(.callout) }
        }
    }

    private func move(_ ids: [PlayerID], from: Int, to: Int) {
        guard ids.indices.contains(to) else { return }
        var next = ids
        next.swapAt(from, to)
        model.perform { try $0.setLineup(next) }
    }
}
