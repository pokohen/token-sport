import SwiftUI
import TokenBaseballCore

/// 경기 전 방침: 투수 운용. 경기는 이 방침대로 흘러간다.
struct PolicyCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        Card(String(localized: "투수 운용 방침")) {
            let policy = game.userTeam.policy
            Stepper("선발 교체 투구 수: \(policy.starterPitchLimit)구", value: binding(\.starterPitchLimit), in: 50...130, step: 5)
            Stepper("선발 교체 실점: \(policy.starterRunLimit)점", value: binding(\.starterRunLimit), in: 2...10)
            Stepper("마무리 투입: \(policy.closerFromInning)회부터", value: binding(\.closerFromInning), in: 7...9)
            Stepper("마무리 투입 점수 차: \(policy.closerMaxLead)점 이내", value: binding(\.closerMaxLead), in: 1...5)
            Text("경기 중에는 개입하지 않습니다. 라인업과 선발은 선수 탭에서 정합니다.").note()
        }
        .font(.callout)
    }

    private func binding(_ keyPath: WritableKeyPath<PitchingPolicy, Int>) -> Binding<Int> {
        Binding(
            get: { game.userTeam.policy[keyPath: keyPath] },
            set: { value in
                model.perform {
                    var policy = $0.userTeam.policy
                    policy[keyPath: keyPath] = value
                    $0.setPitchingPolicy(policy)
                }
            })
    }
}
