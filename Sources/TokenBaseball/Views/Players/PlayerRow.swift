import SwiftUI
import TokenBaseballCore

struct PlayerRow: View {
    let game: Game
    let player: Player
    var trailing: String?

    var body: some View {
        HStack(spacing: 6) {
            PositionTag(position: player.position)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text(player.name).font(.callout.weight(.medium))
                    if player.teamID == game.userTeamID, game.isExpiring(player) { Text("⏳").font(.caption) }
                    if player.isFranchiseStar { Image(systemName: "star.circle.fill").foregroundStyle(Theme.warn).font(.caption) }
                    if player.isHot { Image(systemName: "flame.fill").foregroundStyle(Theme.loss).font(.caption2) }
                    if (player.suspendedMatches ?? 0) > 0 {
                        Text("출장 정지").font(.caption2).foregroundStyle(Theme.loss)
                    }
                    if player.isForeign { Text("외").font(.caption2).padding(.horizontal, 3).background(.quaternary, in: Capsule()) }
                }
                Text("\(player.age)세 · \(player.handedness ?? player.position.label) · \(trailing ?? String(localized: "연봉 \(Format.money(player.contract.salary))"))").note()
            }
            Spacer()
            Stars(count: player.scoutStars(scoutLevel: game.userTeam.scoutLevel))
            Text("\(player.grade) \(Int(player.ability.rounded()))").font(.callout.monospacedDigit().weight(.semibold))
                .frame(width: 44, alignment: .trailing)
        }
        .contentShape(Rectangle())
    }
}
