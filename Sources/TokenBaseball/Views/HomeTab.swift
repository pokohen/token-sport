import SwiftUI
import TokenBaseballCore

struct HomeTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var goToMatch: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            Card {
                HStack(spacing: 12) {
                    EmblemView(team: game.userTeam, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(game.userTeam.name).font(.headline)
                        Text("\(game.userTier.localizedDisplayName) · \(game.season)시즌 · \(game.phaseText)").note()
                    }
                    Spacer()
                    if game.phase == .regular {
                        VStack(alignment: .trailing) {
                            Text("\(game.rank(of: game.userTeamID))위").font(.title3.bold())
                            Text(record).note()
                        }
                    }
                }
            }

            warning

            Card(String(localized: "구단 자금")) {
                Text("₩\(game.funds.balance.formatted())").font(.title2.bold().monospacedDigit())
                    .foregroundStyle(game.funds.balance < 0 ? Theme.loss : .primary)
                KeyValueRow(key: String(localized: "오늘 번 자금 (오늘 쓴 토큰)"), value: "₩\(model.todayTokens.formatted())")
                KeyValueRow(key: String(localized: "누적 토큰 수입"), value: DisplayFormat.money(game.funds.tokenIncome))
                KeyValueRow(key: String(localized: "경기당 연봉"), value: "−₩\(game.salaryPerMatch.formatted())")
                KeyValueRow(key: String(localized: "인지도"), value: "\(Int(game.userTeam.fame))")
            }

            NextMatchCard(game: game, goToMatch: goToMatch)

            NewsCard(game: game)
        }
    }

    private var record: String {
        guard let row = game.standings[game.userTier.index].first(where: { $0.teamID == game.userTeamID }) else { return "" }
        return String(localized: "\(row.wins)승 \(game.sport.hasDraws ? String(localized: "\(row.draws)무 ") : "")\(row.losses)패") + (game.sport.ranksByPoints ? String(localized: " · 승점 \(row.points)") : "")
    }

    @ViewBuilder private var warning: some View {
        switch game.financialState {
        case .warning:
            Banner(text: String(localized: "재정 경고: 자금이 다음 5경기 연봉보다 적습니다."), color: Theme.warn)
        case .crisis(let left):
            Banner(
                text: String(localized: "재정 위기: 자금이 0 아래입니다. 유예 \(left)경기 안에 메우지 못하면 구단이 해체됩니다. 시설 업그레이드와 영입은 할 수 없습니다."),
                color: Theme.loss)
        default:
            EmptyView()
        }
    }
}
