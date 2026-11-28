import SwiftUI
import TokenBaseballCore

/// 은퇴한 뒤: 커리어 기록을 보여 주고 같은 세계에서 새 선수를 만든다.
struct CareerRetiredView: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var setup = CareerSetup(name: "", position: .shortstop)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("은퇴").font(.title2.bold())
                if let record = game.careerHall?.last { CareerRecordCard(record: record) }
                Card(String(localized: "새 선수")) {
                    Text("같은 세계에서 새 선수로 다시 시작합니다. 은퇴한 선수의 기록은 명예의 전당에 남습니다.").note()
                    CareerForm(setup: $setup, sport: game.sport)
                    if setup.pointsLeft > 0 {
                        Text("시작 포인트가 \(setup.pointsLeft)개 남았습니다. 넣지 않은 포인트는 사라집니다.").note()
                    }
                    Button("새 커리어 시작") { model.createCareer(setup) }
                        .buttonStyle(.borderedProminent)
                }
                if let message = model.message {
                    Text(message).font(.callout).foregroundStyle(Theme.loss)
                }
                CareerHallCard(game: game, skipLatest: true)
                Card(String(localized: "다른 모드")) { SlotSwitcher() }
            }
            .padding(16)
        }
    }
}
