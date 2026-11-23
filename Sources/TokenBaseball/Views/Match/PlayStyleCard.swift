import SwiftUI
import TokenBaseballCore

/// 축구·농구 선수 모드: 경기 전에 플레이 스타일을 고른다.
struct PlayStyleCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        let style = game.career?.style ?? .balanced
        Card("플레이 스타일", trailing: game.myPlayer?.position.label) {
            if game.myPlayer?.position == .goalkeeper {
                Text("골키퍼는 플레이 스타일이 없습니다.").note()
            } else {
                Picker("플레이 스타일", selection: Binding(
                    get: { style },
                    set: { value in model.perform { $0.setCareerStyle(value) } })) {
                    ForEach(PlayStyle.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(game.sport == .basketball ? style.basketballSummary : style.summary).note()
            }
            Text(game.sport == .basketball
                ? "선발 다섯 명과 교체는 감독이 정합니다. 경기 중에는 개입하지 않습니다."
                : "포메이션, 전술, 선발 11명은 감독이 정합니다. 경기 중에는 개입하지 않습니다.").note()
        }
        .font(.callout)
    }
}
