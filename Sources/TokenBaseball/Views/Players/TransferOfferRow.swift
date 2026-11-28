import SwiftUI
import TokenBaseballCore

/// 구단 모드: 다른 구단이 내 선수에게 보낸 이적·트레이드 오퍼 한 건과 답하는 버튼.
struct TransferOfferRow: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let offer: TransferOffer

    var body: some View {
        if let player = game.players[offer.playerID] {
            VStack(alignment: .leading, spacing: 4) {
                if let swapID = offer.swapPlayerID, let swap = game.players[swapID] {
                    Text("\(game.teams[offer.fromTeam].name): \(player.name) ↔ \(swap.position.localizedLabel) \(swap.name) (\(swap.grade) \(Int(swap.ability.rounded())), \(swap.age)세)").font(.callout)
                } else {
                    Text("\(game.teams[offer.fromTeam].name): \(player.name)에게 \(DisplayFormat.money(offer.fee))").font(.callout)
                }
                HStack {
                    Button("수락") { model.perform { try $0.respond(to: offer.id, .accept) } }
                    Button("거절") { model.perform { try $0.respond(to: offer.id, .reject) } }
                    if offer.swapPlayerID == nil, !offer.raised {
                        Button("금액 올려 달라고 하기") { model.perform { try $0.respond(to: offer.id, .askMore) } }
                    }
                }
                .controlSize(.small)
            }
        }
    }
}
