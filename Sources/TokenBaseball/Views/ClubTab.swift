import SwiftUI
import TokenBaseballCore

struct ClubTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            Card(String(localized: "시설")) {
                facility(.training, name: Facility.localizedTrainingNames(game.sport)[game.userTeam.trainingLevel - 1],
                         effect: String(localized: "성장 ×\(String(format: "%.2f", Balance.trainingMultiplier[game.userTeam.trainingLevel - 1]))"))
                Divider()
                facility(.stadium, name: Facility.localizedStadiumNames(game.sport)[game.userTeam.stadiumLevel - 1],
                         effect: String(localized: "수용 \(Balance.stadiumCapacity[game.userTeam.stadiumLevel - 1].formatted())명 · 홈 보정 +\(String(format: "%.1f", Balance.stadiumHomeEdge[game.userTeam.stadiumLevel - 1] * 100))%"))
                Divider()
                facility(.scout, name: game.userTeam.scoutLevel == 0 ? String(localized: "없음") : String(localized: "스카우트 팀"),
                         effect: game.userTeam.scoutLevel == 0 ? String(localized: "지으면 스카우트를 보낼 수 있음") : String(localized: "후보 \(3 + game.userTeam.scoutLevel / 2)명, 잠재력 평가가 더 정확"))
            }

            Card(String(localized: "홍보"), trailing: String(localized: "인지도 \(Int(game.userTeam.fame))")) {
                ForEach(Promotion.allCases, id: \.self) { promotion in
                    let blocked = game.promotionBlockedReason(promotion)
                    HStack {
                        VStack(alignment: .leading) {
                            Text(promotion.localizedLabel(game.sport)).font(.callout)
                            Text(blocked ?? (promotion.localizedNote.isEmpty ? String(localized: "인지도 +\(Int(game.promotionEffect(promotion)))") : String(localized: "인지도 +\(Int(game.promotionEffect(promotion))) · \(promotion.localizedNote)"))).note()
                        }
                        Spacer()
                        Button(DisplayFormat.money(game.price(promotion.cost))) {
                            model.perform { try $0.promote(promotion) }
                        }
                        .disabled(blocked != nil || game.funds.balance < game.price(promotion.cost))
                    }
                }
                Text("같은 홍보는 쓸수록 효과가 줄어듭니다 (시즌마다 초기화).").note()
            }

            Card(String(localized: "훈련 방침")) {
                if game.sport == .football {
                    focusSlider(String(localized: "공격"), \.batting)
                    focusSlider(String(localized: "패스"), \.pitching)
                    focusSlider(String(localized: "수비"), \.defense)
                    focusSlider(String(localized: "체력"), \.running)
                    Text("비중이 큰 쪽의 능력치가 더 많이 오릅니다 (공격: 슈팅·드리블, 수비: 수비·골키핑, 체력: 스피드·피지컬·체력). 토큰을 쓰는 동안에는 선수들이 조금 더 빨리 큽니다.").note()
                } else {
                    focusSlider(String(localized: "타격"), \.batting)
                    focusSlider(String(localized: "투구", table: "Club"), \.pitching)
                    focusSlider(String(localized: "수비"), \.defense)
                    focusSlider(String(localized: "주루"), \.running)
                    Text("비중대로 경험치가 나뉩니다. 토큰을 쓰는 동안에는 선수들이 조금 더 빨리 큽니다.").note()
                }
            }

            finance
        }
    }

    private func facility(_ facility: Facility, name: String, effect: String) -> some View {
        HStack {
            VStack(alignment: .leading) {
                Text("\(facility.localizedName) Lv\(game.facilityLevel(facility)) · \(name)").font(.callout.weight(.medium))
                Text(effect).note()
            }
            Spacer()
            if let cost = game.upgradeCost(facility) {
                Button("업그레이드 \(DisplayFormat.money(cost))") { model.perform { try $0.upgrade(facility) } }
                    .disabled(game.funds.balance < cost || game.crisisMatchesLeft != nil)
            } else {
                Text("최고 레벨").note()
            }
        }
    }

    private func focusSlider(_ label: String, _ keyPath: WritableKeyPath<TrainingFocus, Double>) -> some View {
        let total = game.userTeam.focus.batting + game.userTeam.focus.pitching
            + game.userTeam.focus.defense + game.userTeam.focus.running
        let share = total > 0 ? game.userTeam.focus[keyPath: keyPath] / total : 0.25
        return HStack {
            // 영어 이름(Baserunning)이 한 줄에 들어가는 폭.
            Text(label).font(.callout).lineLimit(1).frame(width: 84, alignment: .leading)
            Slider(
                value: Binding(
                    get: { game.userTeam.focus[keyPath: keyPath] },
                    set: { value in
                        model.perform {
                            var focus = $0.userTeam.focus
                            focus[keyPath: keyPath] = value
                            $0.setTrainingFocus(focus)
                        }
                    }),
                in: 0.05...1)
            Text("\(Int((share * 100).rounded()))%").font(.callout.monospacedDigit()).frame(width: 40, alignment: .trailing)
        }
    }

    private var finance: some View {
        Card(String(localized: "이번 시즌 재정")) {
            let income = FundsLedger.Category.allCases.compactMap { category in
                game.funds.seasonIncome[category.rawValue].map { (category, $0) }
            }
            let expense = FundsLedger.Category.allCases.compactMap { category in
                game.funds.seasonExpense[category.rawValue].map { (category, $0) }
            }
            let totalIncome = income.reduce(0) { $0 + $1.1 }
            let totalExpense = expense.reduce(0) { $0 + $1.1 }
            Text("수입 \(DisplayFormat.money(totalIncome))").font(.caption.bold())
            ForEach(income, id: \.0) { category, amount in
                KeyValueRow(
                    key: "\(category.localizedName) (\(totalIncome > 0 ? amount * 100 / totalIncome : 0)%)",
                    value: "₩\(amount.formatted())", valueColor: Theme.win)
            }
            if income.isEmpty { Text("아직 수입이 없습니다.").note() }
            Divider()
            Text("지출 \(DisplayFormat.money(totalExpense))").font(.caption.bold())
            ForEach(expense, id: \.0) { category, amount in
                KeyValueRow(key: category.localizedName, value: "−₩\(amount.formatted())", valueColor: Theme.loss)
            }
            if expense.isEmpty { Text("아직 지출이 없습니다.").note() }
            Divider()
            KeyValueRow(key: String(localized: "오늘 토큰으로 번 금액"), value: "₩\(model.todayTokens.formatted())")
            KeyValueRow(key: String(localized: "경기당 연봉"), value: "−₩\(game.salaryPerMatch.formatted())")
        }
    }
}
