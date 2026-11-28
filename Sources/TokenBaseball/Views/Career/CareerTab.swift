import SwiftUI
import TokenBaseballCore

struct CareerTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var confirmRetire = false

    var body: some View {
        VStack(spacing: 10) {
            if let career = game.career, let me = game.myPlayer {
                if !career.offers.isEmpty { offers(career) }
                contract(career, me)
                CareerScoutCard(game: game, career: career)
                CareerRivalCard(game: game, career: career, me: me)
                CareerActivityCard(game: game, career: career)
                season(career, me)
                history(career, me)
                rivals(me)
            }
            CareerHallCard(game: game)
        }
    }

    private func offers(_ career: Career) -> some View {
        Card(career.isFreeAgent ? String(localized: "입단 제안") : String(localized: "들어온 제안")) {
            ForEach(career.offers) { offer in
                CareerOfferRow(game: game, offer: offer)
                if offer.id != career.offers.last?.id { Divider() }
            }
        }
    }

    private func contract(_ career: Career, _ me: Player) -> some View {
        Card(String(localized: "계약")) {
            KeyValueRow(key: String(localized: "소속"), value: career.isFreeAgent ? String(localized: "무소속") : game.userTeam.name)
            KeyValueRow(key: String(localized: "연봉"), value: Format.money(me.contract.salary))
            // "N시즌"이 여기서는 남은 기간이고 다른 곳에서는 몇 번째 시즌이라, 영어가 달라서 표를 나눈다.
            KeyValueRow(
                key: String(localized: "남은 계약"),
                value: me.contract.seasonsLeft <= 0
                    ? String(localized: "만료") : String(localized: "\(me.contract.seasonsLeft)시즌", table: "Counts"),
                valueColor: me.contract.seasonsLeft <= 1 ? Theme.warn : .primary)
            KeyValueRow(key: String(localized: "통산 수입"), value: Format.money(career.earnings))
            if !career.isFreeAgent {
                HStack {
                    Button("이적 요청") { model.perform { try $0.requestCareerTransfer() } }
                        .disabled(!game.tradeWindowOpen || career.transferRequested)
                    Button(String(localized: "은퇴", table: "Actions")) { confirmRetire = true }
                        .disabled(confirmRetire || !game.canRetireCareer)
                        .help(game.careerRetireBlockedReason ?? String(localized: "은퇴하고 명예의 전당에 기록을 남깁니다"))
                }
                if confirmRetire {
                    InlineConfirm(
                        message: String(localized: "은퇴할까요? 되돌릴 수 없습니다. 기록은 명예의 전당에 남고, 같은 세계에서 새 선수로 시작할 수 있습니다."),
                        confirmTitle: String(localized: "은퇴", table: "Actions"), cancel: { confirmRetire = false }
                    ) {
                        confirmRetire = false
                        model.perform { try $0.retireCareer() }
                    }
                }
                if let reason = game.careerRetireBlockedReason {
                    Text("은퇴: \(reason)").note()
                }
                Text(career.transferRequested
                    ? "이적을 요청해 두었습니다. 이적 기간 동안 스카우트가 더 잘 오고, 더 낮은 관심도에서도 제안합니다."
                    : game.tradeWindowOpen
                    ? (career.fans != nil
                        ? "이적을 요청하면 스카우트들의 관심이 오르고 제안의 문턱이 낮아집니다. 이적 기간마다 한 번."
                        : "이적을 요청하면 스카우트들의 관심이 오르고 제안의 문턱이 낮아지지만, 감독 신뢰가 10 떨어집니다. 이적 기간마다 한 번.")
                    : "지금은 이적 기간이 아닙니다 (정규시즌 \(Balance.tradeDeadlineRound)라운드까지, 그리고 오프시즌).").note()
            }
        }
    }

    private func season(_ career: Career, _ me: Player) -> some View {
        Card(String(localized: "이번 시즌"), trailing: game.userTier.displayName(for: game.sport)) {
            KeyValueRow(key: String(localized: "기록"), value: CareerText.record(
                me, batting: me.batting, pitching: me.pitching, football: me.football, basketball: me.basketball))
            if let line = me.basketball {
                KeyValueRow(
                    key: String(localized: "출전 시간 · 야투 · 3점슛"),
                    value: String(localized: "평균 \(String(format: "%.1f", line.minutesPerGame))분 · \(Int((line.fieldGoalRate * 100).rounded()))% · \(Int((line.threeRate * 100).rounded()))%"))
                KeyValueRow(key: String(localized: "스틸 · 블록 · 실책"), value: "\(line.steals) · \(line.blocks) · \(line.turnovers)")
            } else if let line = me.duel {
                ForEach(DuelRace.allCases, id: \.self) { race in
                    KeyValueRow(key: String(localized: "대 \(race.label)"), value: line.versusText(race).replacingOccurrences(of: "대 \(race.label) ", with: ""))
                }
            } else if let line = me.football {
                KeyValueRow(key: String(localized: "유효 슈팅 · 경고 · 퇴장"), value: "\(line.shotsOnTarget) · \(line.yellowCards) · \(line.redCards)")
            } else if me.isPitcher {
                KeyValueRow(key: String(localized: "이닝 · 탈삼진"), value: String(localized: "\(me.pitching.innings)이닝 · \(me.pitching.strikeouts)개"))
            } else {
                KeyValueRow(key: String(localized: "OPS · 도루"), value: String(localized: "\(String(format: "%.3f", me.batting.ops)) · \(me.batting.steals)개"))
            }
            KeyValueRow(key: String(localized: "평균 평점"), value: CareerText.rating(career.seasonAverageRating))
        }
    }

    private func history(_ career: Career, _ me: Player) -> some View {
        let totals = game.careerTotals
        return Card(String(localized: "통산")) {
            KeyValueRow(key: String(localized: "기록"), value: CareerText.record(
                me, batting: totals.batting, pitching: totals.pitching, football: game.careerFootballTotals,
                basketball: game.careerBasketballTotals))
            KeyValueRow(
                key: String(localized: "평균 평점"),
                value: CareerText.rating(totals.ratedGames == 0 ? nil : totals.ratingTotal / Double(totals.ratedGames)))
            KeyValueRow(key: String(localized: "가장 높이 오른 리그"), value: career.bestTier.displayName(for: game.sport))
            if !career.clubs.isEmpty { Text(career.clubs.joined(separator: " → ")).note() }
            if !career.awards.isEmpty { Text(String(localized: "수상: ") + career.awards.joined(separator: " · ")).note() }
            if !career.history.isEmpty {
                Divider()
                // 시즌 도중에 옮기면 한 시즌이 두 줄이라 시즌 번호를 id로 쓸 수 없다.
                ForEach(Array(career.history.enumerated().reversed()), id: \.offset) { _, item in
                    VStack(alignment: .leading, spacing: 1) {
                        Text("\(item.season)시즌 · \(item.age)세 · \(item.teamName) (\(item.tier.rawValue)부)").font(.caption.weight(.semibold))
                        Text(CareerText.record(
                            me, batting: item.batting, pitching: item.pitching, football: item.football,
                            basketball: item.basketball)
                            + String(localized: " · 평점 \(CareerText.rating(item.averageRating))")).note()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    @ViewBuilder private func rivals(_ me: Player) -> some View {
        if let team = me.teamID {
            let sport = me.position.sport
            let byPosition = sport.groupsByPosition
            let peers = game.roster(of: team).filter { byPosition ? $0.position == me.position : $0.isPitcher == me.isPitcher }
                .sorted { ($0.ability, -$0.id) > ($1.ability, -$1.id) }
            Card(byPosition ? String(localized: "주전 경쟁 (\(me.position.label))") : me.isPitcher ? String(localized: "팀 투수진") : String(localized: "팀 타선")) {
                switch sport {
                case .basketball:
                    Text("\(me.position.label) 선발은 한 명입니다. 같은 포지션에서 가장 좋은 선수를 넘어서야 선발로 나오고, 감독 신뢰가 높으면 능력이 조금 낮아도 선발입니다. 벤치에서도 감독 신뢰만큼 출전 시간을 받습니다.").note()
                case .football:
                    let quota = game.formation(of: team).slots.filter { $0 == me.position }.count
                    Text("포메이션 \(game.formation(of: team).label): \(me.position.label) 선발은 \(quota)명입니다. 감독 신뢰가 높으면 능력이 조금 낮아도 선발로 나옵니다.").note()
                case .duel:
                    Text("팀 경기는 세트마다 한 명씩 나갑니다. 팀에서 가장 잘하는 선수가 에이스 결정전에 나갑니다.").note()
                case .baseball:
                    EmptyView()
                }
                ForEach(peers) { player in
                    PlayerLine(player: player, highlighted: player.id == me.id)
                }
            }
        }
    }
}
