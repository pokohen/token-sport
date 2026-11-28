import SwiftUI
import TokenBaseballCore

struct PlayersTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var section = Section.roster
    @State private var openPlayer: PlayerID?
    @State private var expiringOnly = false

    enum Section: String, CaseIterable {
        case roster = "로스터", lineup = "라인업", market = "영입·이적"

        var title: String {
            switch self {
            case .roster: String(localized: "로스터")
            case .lineup: String(localized: "라인업")
            case .market: String(localized: "영입·이적")
            }
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Picker("", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch section {
            case .roster: roster
            case .lineup: LineupView(game: game)
            case .market: MarketView(game: game)
            }
        }
    }

    private var roster: some View {
        let all = game.roster(of: game.userTeamID)
        let shown = all.filter { !expiringOnly || game.isExpiring($0) }
            .sorted { (Self.group($0), -$0.ability) < (Self.group($1), -$1.ability) }
        return Card(String(localized: "선수단"), trailing: String(localized: "\(all.count) / \(game.rosterLimit(game.userTier))명")) {
            Toggle("계약 만료 예정만 보기 (\(all.filter { game.isExpiring($0) }.count)명)", isOn: $expiringOnly)
                .font(.callout)
            ForEach(shown) { player in
                Button {
                    openPlayer = openPlayer == player.id ? nil : player.id
                } label: {
                    PlayerRow(game: game, player: player)
                }
                .buttonStyle(.plain)
                if openPlayer == player.id { PlayerDetail(game: game, player: player) }
            }
            Text("⏳ 이번 시즌이 계약 마지막. 재계약하지 않으면 오프시즌이 끝날 때 떠납니다.").note()
        }
    }
}

extension PlayersTab {
    /// 로스터를 묶어 보여줄 순서: 야구는 야수 → 투수, 축구는 골키퍼 → 수비 → 미드필더 → 공격.
    static func group(_ player: Player) -> Int {
        if player.position.sport == .football { return Position.football.firstIndex(of: player.position) ?? 0 }
        return player.isPitcher ? 1 : 0
    }
}
