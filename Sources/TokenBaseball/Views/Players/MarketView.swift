import SwiftUI
import TokenBaseballCore

/// 영입 경로와 이적 시장.
struct MarketView: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            Card(String(localized: "이적 시장"), trailing: game.tradeWindowOpen ? String(localized: "열림") : String(localized: "닫힘")) {
                Text(windowText).note()
            }

            if !game.offers.isEmpty {
                Card(String(localized: "들어온 오퍼")) {
                    ForEach(game.offers) { offer in
                        TransferOfferRow(game: game, offer: offer)
                    }
                    Text("다음 경기가 끝날 때까지 답하지 않으면 자동으로 거절됩니다.").note()
                }
            }

            if !game.proposals.isEmpty {
                Card(String(localized: "보낸 제안")) {
                    ForEach(game.proposals) { proposal in
                        HStack {
                            Text("\(proposal.kind.localizedName) · \(game.players[proposal.playerID]?.name ?? "")").font(.callout)
                            Spacer()
                            Button("취소") { model.perform { $0.withdrawProposal(proposal.id) } }.controlSize(.small)
                        }
                    }
                    Text("답은 다음 경기가 끝난 뒤에 옵니다.").note()
                }
            }

            Card(String(localized: "입단 테스트")) {
                HStack {
                    Text("지역 선수 후보 3~5명이 옵니다. 능력은 낮지만 잠재력 높은 선수가 가끔 섞여 있습니다.").note()
                    Spacer()
                    Button("테스트 열기 \(DisplayFormat.money(game.tryoutFee))") { model.perform { try $0.holdTryout() } }
                        .disabled(game.candidates.contains { $0.source == .tryout })
                }
            }

            Card(String(localized: "스카우트"), trailing: String(localized: "시설 Lv\(game.userTeam.scoutLevel)")) {
                if game.userTeam.scoutLevel == 0 {
                    Text("구단 탭에서 스카우트 시설을 지으면 보낼 수 있습니다.").note()
                } else if let trip = game.scoutTrip {
                    Text("\(trip.region.localizedName) 스카우트가 \(trip.matchesLeft)경기 뒤에 돌아옵니다.").font(.callout)
                } else {
                    HStack {
                        ForEach(ScoutRegion.allCases, id: \.self) { region in
                            Button("\(region.localizedName) \(DisplayFormat.money(game.scoutCost(region)))") {
                                model.perform { try $0.sendScout(region) }
                            }
                            .disabled(region == .overseas && game.userTier > .semiPro)
                        }
                    }
                    .controlSize(.small)
                    Text("해외 스카우트와 외국인 선수(팀당 3명)는 1~2부에서만.").note()
                }
            }

            if !game.candidates.isEmpty {
                Card(String(localized: "영입 후보")) {
                    ForEach(game.candidates) { candidate in
                        if let player = game.players[candidate.playerID] {
                            HStack {
                                PlayerRow(
                                    game: game, player: player,
                                    trailing: String(localized: "\(candidate.source == .draft && game.sport == .football ? String(localized: "유소년 승급") : candidate.source.localizedName) · 연봉 \(DisplayFormat.money(player.contract.salary))"))
                                // 카드 제목 "계약"(Contract)과 영어가 달라서 (Sign) 표를 나눈다.
                                Button {
                                    model.perform { try $0.sign(candidate: candidate.id) }
                                } label: {
                                    candidate.fee > 0
                                        ? Text("계약 \(DisplayFormat.money(game.price(candidate.fee)))", tableName: "Actions")
                                        : Text("계약", tableName: "Actions")
                                }
                                .controlSize(.small)
                            }
                        }
                    }
                }
            }

            if game.phase == .offseason {
                Card(String(localized: "자유계약 (FA)"), trailing: String(localized: "\(game.freeAgentMarket.count)명")) {
                    ForEach(game.freeAgentMarket.prefix(15)) { player in
                        let market = Balance.marketSalary(ability: player.ability)
                        HStack {
                            PlayerRow(game: game, player: player, trailing: String(localized: "시장가 \(DisplayFormat.money(market))"))
                            if game.proposals.contains(where: { $0.playerID == player.id }) {
                                Text("제안함").note()
                            } else {
                                Menu("제안") {
                                    Button("시장가 (\(DisplayFormat.money(market)), 2시즌)") {
                                        model.perform { try $0.proposeFreeAgent(player.id, salary: market, years: 2) }
                                    }
                                    Button("20% 더 (\(DisplayFormat.money(market * 12 / 10)), 2시즌)") {
                                        model.perform { try $0.proposeFreeAgent(player.id, salary: market * 12 / 10, years: 2) }
                                    }
                                    Button("50% 더 (\(DisplayFormat.money(market * 15 / 10)), 2시즌)") {
                                        model.perform { try $0.proposeFreeAgent(player.id, salary: market * 15 / 10, years: 2) }
                                    }
                                }
                                .fixedSize()
                                .controlSize(.small)
                            }
                        }
                    }
                    Text("인지도가 높고 리그가 높을수록, 많이 줄수록 영입 성공률이 올라갑니다.").note()
                }
            }
            Text("다른 구단 선수에게 이적 제안을 하려면 리그 탭에서 팀을 누르세요.").note()
        }
    }

    private var windowText: String {
        switch game.phase {
        case .offseason:
            String(localized: "오프시즌 이적 시장입니다. FA 영입, 이적 오퍼, 재계약을 할 수 있고, 친선 경기가 끝날 때마다 소식이 들어옵니다.")
        case .regular where game.round < Balance.tradeDeadlineRound:
            String(localized: "시즌 중 트레이드 기간입니다 (\(Balance.tradeDeadlineRound)라운드까지). 가끔 트레이드 제안이 옵니다.")
        default:
            String(localized: "트레이드 마감이 지났습니다. 다음 이적 시장은 시즌이 끝난 뒤에 열립니다.")
        }
    }
}
