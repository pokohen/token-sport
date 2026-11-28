import SwiftUI
import TokenBaseballCore

/// 커리어 탭: 훈련 포인트를 들여 명성을 올리는 활동. 경기 사이에 한 번.
struct CareerActivityCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    let career: Career

    var body: some View {
        let cap = Balance.careerFameCap(game.userTier)
        let duel = career.fans != nil
        return Card(duel ? String(localized: "팬 활동") : String(localized: "명성 활동"),
                    trailing: duel ? String(localized: "팬 \(DisplayFormat.fans(career.fans ?? 0))") : String(localized: "명성 \(Int(career.fame)) / 이 리그 한도 \(Int(cap))")) {
            Text(duel
                ? "훈련 포인트를 들여 팬을 늘립니다. 경기 사이에 한 번 할 수 있습니다. 팬은 경기와 개인 대회로 버는 것이 가장 큽니다."
                : "훈련 포인트를 들여 명성을 올립니다. 경기 사이에 한 번 할 수 있고, 명성이 높을수록 더 큰 구단에서 제안이 옵니다.").note()
            ForEach(CareerActivity.allCases, id: \.self) { activity in
                let blocked = game.careerActivityBlockedReason(activity)
                HStack(spacing: 8) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(activity.localizedLabel(for: game.sport)).font(.callout.weight(.medium))
                        Text(activity.localizedDetail(for: game.sport)).note()
                    }
                    Spacer()
                    let gain = game.careerActivityFans(activity).map { String(localized: "팬 +\(DisplayFormat.fans($0))") }
                        ?? String(localized: "명성 +\(String(format: "%.1f", game.careerActivityGain(activity)))")
                    Button("\(gain) · \(Format.tokens(game.careerActivityCost(activity))) P") {
                        model.perform { try $0.doCareerActivity(activity) }
                    }
                    .disabled(blocked != nil)
                    .help(blocked ?? activity.localizedDetail)
                }
            }
            if let reason = CareerActivity.allCases.compactMap({ game.careerActivityBlockedReason($0) }).first,
               career.activityDone == true || career.isFreeAgent || (!duel && career.fame >= cap) {
                Text(reason).note()
            }
        }
    }
}
