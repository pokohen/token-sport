import SwiftUI
import TokenBaseballCore

/// 중계 배속 고르기와 결과 바로 보기. 경기 도중에도 쓸 수 있다.
struct MatchSpeedCard: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        Card {
            HStack {
                Text("배속").font(.callout).foregroundStyle(.secondary)
                Picker("배속", selection: $model.matchSpeed) {
                    ForEach(AppModel.matchSpeeds, id: \.self) { Text("\($0)×").tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if let game = model.game {
                let blocked = game.skipMatchBlockedReason
                HStack {
                    Text("기다리지 않고 남은 경기를 끝까지 치릅니다. 결과는 지켜봤을 때와 같습니다.").note()
                    Spacer(minLength: 8)
                    Button("결과 바로 보기 · \(game.fundsText(game.skipMatchCost))") { model.skipMatch() }
                        .disabled(blocked != nil)
                        .help(blocked ?? "토큰을 내고 경기 결과를 바로 봅니다")
                }
            }
        }
    }
}
