import SwiftUI
import TokenBaseballCore

struct SettingsTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            Card(String(localized: "상단바")) {
                Picker("보일 숫자", selection: setting(\.menuBarDisplay)) {
                    ForEach(MenuBarDisplay.allCases, id: \.self) {
                        Text(game.isCareer && $0 == .funds ? String(localized: "훈련 포인트") : $0.rawValue).tag($0)
                    }
                }
                Toggle("훈련 애니메이션", isOn: setting(\.animationEnabled))
                Toggle("알림 (\(game.sport.notificationKinds))", isOn: setting(\.notificationsEnabled))
                if !Notifier.isAvailable {
                    Text("알림은 앱 번들(.app)로 실행할 때만 나옵니다.").note()
                }
                Text("경기 중과 경기 종료 표시는 이 설정과 상관없이 나옵니다.").note()
            }
            .font(.callout)

            Card(String(localized: "모드"), trailing: String(localized: "지금: \(model.slot.label)")) {
                SlotSwitcher()
            }
            .font(.callout)

            Card(String(localized: "난이도")) {
                if !game.isCareer {
                    Picker("CPU 팀 맞춰주기", selection: setting(\.rubberBand)) {
                        ForEach(RubberBand.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                }
                HStack {
                    Text("가격 난이도")
                    Slider(value: setting(\.priceDifficulty), in: 0.1...2.0, step: 0.1)
                    Text("\(Int((game.settings.priceDifficulty * 100).rounded()))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Text(game.isCareer
                    ? "훈련 비용에 곱합니다. 토큰 수는 그대로입니다."
                    : "시설·홍보·영입·연봉 비용에 곱합니다. 토큰 수는 그대로입니다.").note()
                if game.isCareer { Divider() }
                if game.isCareer {
                    Toggle("추가 훈련 (횟수를 넘겨서도 훈련)", isOn: Binding(
                        get: { game.careerExtraTrainingEnabled },
                        set: { on in model.perform { $0.setCareerExtraTraining(on) } }))
                    Text("꺼 두면 경기 사이에 \(Balance.careerSessionsPerMatch)번까지만 훈련합니다. 켜면 그 뒤로도 훈련할 수 있고, 한 번마다 비용이 \(String(format: "%g", Balance.careerExtraSessionCost))배씩 더 듭니다 (1.5배, 2.25배, 3.4배…). 다음 경기를 치르면 처음 값으로 돌아갑니다.").note()
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .font(.callout)

            RenameCard(game: game)

            UpdateCard()

            Card(String(localized: "토큰 경로")) {
                Text(model.sources.claudeCode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(model.sources.codex.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(model.sources.gemini.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(model.sources.opencode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                Text(game.isCareer
                     ? String(localized: "이 컴퓨터 안에서만 읽고 외부로 보내지 않습니다. 선수를 만든 뒤에 쓴 토큰만 셉니다.")
                     : String(localized: "이 컴퓨터 안에서만 읽고 외부로 보내지 않습니다. 구단을 만든 뒤에 쓴 토큰만 셉니다.")).note()
                Text("저장 파일: \(model.store.fileURL.path)").font(.caption2.monospaced()).textSelection(.enabled)
            }

            ResetCard(game: game)

            if !game.hallOfFame.isEmpty {
                Card(String(localized: "명예의 전당")) {
                    ForEach(Array(game.hallOfFame.enumerated()), id: \.offset) { _, entry in
                        Text("\(entry.name) · \(entry.foundedSeason)~\(entry.endedSeason)시즌 · 최고 \(entry.bestTier.displayName)\(entry.star.map { String(localized: " · 간판 \($0)") } ?? "")").font(.callout)
                    }
                }
            }

            Card {
                Text("Token Sports는 \(game.sport.leagueDisclaimer) 비공식 팬 프로젝트입니다. 등장하는 구단과 선수는 모두 가상입니다.").note()
                Button("앱 종료") {
                    model.save()
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    private func setting<Value>(_ keyPath: WritableKeyPath<TokenBaseballCore.Settings, Value>) -> Binding<Value> {
        Binding(
            get: { game.settings[keyPath: keyPath] },
            set: { value in model.perform { $0.settings[keyPath: keyPath] = value } })
    }
}
