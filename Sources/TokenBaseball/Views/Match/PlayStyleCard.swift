import SwiftUI
import TokenBaseballCore

/// 축구·농구 선수 모드: 경기 전에 플레이 스타일을 고른다.
struct PlayStyleCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        let style = game.career?.style ?? .balanced
        Card("플레이 스타일", trailing: game.myPlayer?.position.label) {
            if game.sport == .duel {
                duel
            } else if game.myPlayer?.position == .goalkeeper {
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
            Text(game.sport == .duel
                ? "세트 배정은 감독이 정합니다. 경기 중에는 개입하지 않습니다."
                : game.sport == .basketball
                ? "선발 다섯 명과 교체는 감독이 정합니다. 경기 중에는 개입하지 않습니다."
                : "포메이션, 전술, 선발 11명은 감독이 정합니다. 경기 중에는 개입하지 않습니다.").note()
        }
        .font(.callout)
    }

    /// e스포츠: 빌드를 고르는 성향.
    @ViewBuilder private var duel: some View {
        let style = game.career?.duelStyle ?? .balanced
        Picker("플레이 스타일", selection: Binding(
            get: { style },
            set: { value in model.perform { $0.setCareerDuelStyle(value) } })) {
            ForEach(DuelStyle.allCases, id: \.self) { Text($0.label).tag($0) }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        let summary = switch style {
        case .balanced: "빌드를 고르게 씁니다."
        case .rush: "초반 공격 빌드가 잦습니다. 상대가 막으면 그대로 불리해집니다."
        case .macro: "확장을 먼저 하고 장기전으로 갑니다. 초반 공격에 약합니다."
        case .gambit: "깜짝 빌드와 기습이 잦습니다. 성공하면 크게 이기고, 읽히면 크게 집니다."
        }
        Text(summary).note()
    }
}
