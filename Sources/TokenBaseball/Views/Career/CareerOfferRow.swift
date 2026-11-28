import SwiftUI
import TokenBaseballCore

/// 선수 모드: 내 선수에게 온 계약 제안 한 건과 답하는 버튼.
struct CareerOfferRow: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let offer: CareerOffer

    var body: some View {
        let team = game.teams[offer.teamID]
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                EmblemView(team: team, size: 24)
                VStack(alignment: .leading) {
                    Text(team.name).font(.callout.weight(.medium))
                    Text("\(kindLabel) · \(team.tier.localizedDisplayName(for: game.sport)) · \(game.rank(of: team.id))위").note()
                }
                Spacer()
            }
            KeyValueRow(key: String(localized: "연봉 · 기간"), value: String(localized: "\(DisplayFormat.money(offer.salary)) · \(offer.years)시즌"))
            KeyValueRow(key: String(localized: "예상 입지"), value: offer.role.localizedName)
            HStack {
                Button("수락") { model.perform { try $0.acceptCareerOffer(offer.id) } }
                    .buttonStyle(.borderedProminent)
                Button("연봉 올려 달라고 하기") { model.perform { try $0.negotiateCareerOffer(offer.id) } }
                    .disabled(offer.negotiated)
                if offer.kind != .tryout {
                    Button("거절") { model.perform { try $0.declineCareerOffer(offer.id) } }
                }
            }
            if offer.kind == .transfer { Text("다음 경기가 끝나면 사라집니다.").note() }
        }
    }

    private var kindLabel: String {
        switch offer.kind {
        case .transfer: String(localized: "이적 제안")
        case .renewal: String(localized: "재계약 제안")
        case .tryout: String(localized: "입단 제안")
        }
    }
}
