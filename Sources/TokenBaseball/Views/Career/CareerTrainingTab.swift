import SwiftUI
import TokenBaseballCore

struct CareerTrainingTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            if let career = game.career, let me = game.myPlayer {
                Card("훈련", trailing: sessionsText(career)) {
                    KeyValueRow(key: "훈련 포인트", value: "\(Format.tokens(game.funds.balance)) P")
                    if let critical = career.lastCritical {
                        Label(critical, systemImage: "sparkles")
                            .font(.callout.weight(.semibold)).foregroundStyle(Theme.warn)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    Divider()
                    ForEach(game.careerTrainableKeys, id: \.self) { key in
                        drillRow(key, me)
                    }
                    Text(trainingNote(career, me)).note().fixedSize(horizontal: false, vertical: true)
                }

                Card("한계 돌파 훈련") {
                    Text("큰 포인트를 들여 능력의 한계를 조금 넓힙니다. 능력치가 더 오르지 않을 때 씁니다. 훈련 횟수를 한 번 씁니다.").note()
                    HStack {
                        Text("한계 +1").font(.callout)
                        Spacer()
                        Button("\(Format.tokens(game.careerBreakthroughCost)) P") {
                            model.perform { try $0.breakThroughCareer() }
                        }
                        .disabled(game.careerBreakthroughBlockedReason != nil)
                    }
                    if let reason = game.careerBreakthroughBlockedReason { Text(reason).note() }
                }

                Card("내 선수") {
                    KeyValueRow(key: "능력", value: "\(String(format: "%.1f", me.ability)) (\(me.grade))")
                    KeyValueRow(key: "시즌 시작 때보다", value: String(format: "%+.1f", me.ability - me.abilityAtSeasonStart))
                    KeyValueRow(key: "최고 능력", value: "\(Int(career.peakAbility))")
                    KeyValueRow(key: "지금까지 훈련", value: "\(career.trainingCount)회 (크리티컬 \(career.criticalCount ?? 0)회)")
                    Text("어떤 훈련이든 능력은 같은 양만큼 오릅니다. 훈련하지 않아도 경기를 뛰면 조금씩 큽니다. \(Balance.declineStartAge(me.position))세부터는 시즌마다 능력치가 크게 떨어집니다.").note()
                }
            }
        }
    }

    private func drillRow(_ key: Attributes.Key, _ me: Player) -> some View {
        let value = me.attributes[key]
        let blocked = game.careerTrainingBlockedReason(key)
        return HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(CareerDrill.name(key, sport: game.sport)).font(.callout.weight(.medium))
                Text("\(label(key)) \(String(format: "%.2f", value))").note()
            }
            .frame(width: 118, alignment: .leading)
            Bar(fraction: value / 99, color: .accentColor)
            // 버튼 너비를 맞춰 둔다. 글자 수에 따라 버튼이 달라지면 막대의 오른쪽 끝이 줄마다 어긋난다.
            Button {
                model.perform { try $0.trainCareer(key) }
            } label: {
                Text("+\(String(format: "%.2f", game.careerTrainingGain(key))) · \(Format.tokens(game.careerTrainingCost(key))) P")
                    .monospacedDigit().lineLimit(1).minimumScaleFactor(0.8)
                    .frame(width: 104)
            }
            .disabled(blocked != nil)
            .help(blocked ?? "\(label(key)) +\(String(format: "%.2f", game.careerTrainingGain(key)))")
        }
    }

    /// 주력과 스피드는 같은 능력치다. 종목에 맞는 이름으로 보여 준다.
    private func label(_ key: Attributes.Key) -> String {
        if game.sport == .basketball, key == .shooting { return "슛" }
        return game.sport != .baseball && key == .speed ? "스피드" : key.label
    }

    private func sessionsText(_ career: Career) -> String {
        career.sessionsLeft <= 0 && game.careerExtraTrainingEnabled
            ? "추가 훈련 \(game.careerExtraSessionsUsed)번 · 비용 ×\(String(format: "%.1f", game.careerSessionCostMultiplier))"
            : "남은 횟수 \(max(0, career.sessionsLeft))/\(Balance.careerSessionsPerMatch)"
    }

    private func trainingNote(_ career: Career, _ me: Player) -> String {
        if me.age >= Balance.careerTrainingAgeLimit(me.position) {
            return "\(Balance.careerTrainingAgeLimit(me.position))세부터는 훈련으로 능력치를 올릴 수 없습니다."
        }
        if career.sessionsLeft <= 0, game.careerExtraTrainingEnabled {
            return "정해진 \(Balance.careerSessionsPerMatch)번을 다 써서 지금부터는 추가 훈련입니다. 비용이 \(String(format: "%.1f", game.careerSessionCostMultiplier))배이고, 한 번 할 때마다 \(Balance.careerExtraSessionCost)배씩 더 비싸집니다. 다음 경기를 치르면 처음 값으로 돌아갑니다."
        }
        if career.sessionsLeft <= 0 { return "오늘 훈련을 마쳤습니다. 다음 경기를 치르면 다시 \(Balance.careerSessionsPerMatch)번 훈련할 수 있습니다. 설정 탭에서 \"추가 훈련\"을 켜면 더 비싼 값에 이어서 할 수 있습니다." }
        return "경기와 경기 사이에 \(Balance.careerSessionsPerMatch)번까지 훈련합니다. 어떤 훈련이든 능력이 \(String(format: "%.3f", game.careerTrainingStep))씩 오르고, 그 능력치가 높을수록 포인트가 많이 듭니다. 윗 리그로 갈수록 한 번에 더 많이 오르고 더 비쌉니다 (지금 \(game.userTier.rawValue)부: 비용 \(String(format: "%.1f", game.careerTrainingCostFactor))배). 100번에 한 번꼴로 크리티컬이 터져 세 배 오릅니다. 쓰지 않은 포인트는 그대로 남습니다."
    }
}
