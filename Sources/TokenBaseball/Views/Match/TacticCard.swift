import SwiftUI
import TokenBaseballCore

/// 축구의 경기 전 방침: 포메이션과 전술 성향.
struct TacticCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        let formation = game.userTeam.formation ?? .f442
        Card(String(localized: "전술"), trailing: formation.label) {
            Picker("포메이션", selection: Binding(
                get: { formation },
                set: { value in model.perform { $0.setFormation(value) } })
            ) {
                ForEach(Formation.allCases, id: \.self) { Text($0.label).tag($0) }
            }
            .pickerStyle(.menu)
            .fixedSize()
            Text(formation.localizedSummary).note()
            if let next = game.nextMatch() {
                Text("다음 상대 \(game.teams[next.opponent].shortName)의 예상 포메이션: \(game.formation(of: next.opponent).label)").note()
            }
            Picker("전술 성향", selection: Binding(
                get: { game.userTeam.tactic ?? .balanced },
                set: { value in model.perform { $0.setTactic(value) } })
            ) {
                ForEach(Tactic.allCases, id: \.self) { Text($0.localizedName).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Text("공격적이면 슈팅 기회가 늘지만 실점 위험도 커집니다. 수비적이면 그 반대입니다.").note()
            Text("경기 중에는 개입하지 않습니다. 선발 11명은 선수 탭에서 정합니다. 지친 선수는 60분 이후 자동으로 교체됩니다.").note()
        }
        .font(.callout)
    }
}
