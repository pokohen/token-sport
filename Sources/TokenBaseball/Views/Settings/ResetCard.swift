import AppKit
import SwiftUI
import TokenBaseballCore

/// 설정 탭: 지금 모드만, 또는 전부 처음부터 다시 시작한다. 저장 파일은 backups 폴더로 옮겨 둔다.
struct ResetCard: View {
    enum Pending { case slot, all }

    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var pending: Pending?

    init(game: Game, pending: Pending? = nil) {
        self.game = game
        _pending = State(initialValue: pending)
    }

    var body: some View {
        Card(String(localized: "초기화")) {
            HStack {
                Button("\(model.slot.label) 처음부터 다시") { pending = .slot }
                Button("전체 초기화") { pending = .all }
            }
            .disabled(pending != nil)
            switch pending {
            case .slot:
                InlineConfirm(
                    message: game.isCareer
                        ? String(localized: "지금 하던 \(model.slot.label)를 그만두고 처음부터 다시 시작할까요? 다른 모드는 그대로입니다. 저장 파일은 지우지 않고 backups 폴더로 옮겨 둡니다.")
                        : String(localized: "지금 하던 \(model.slot.label)을 그만두고 처음부터 다시 시작할까요? 다른 모드는 그대로입니다. 저장 파일은 지우지 않고 backups 폴더로 옮겨 둡니다."),
                    confirmTitle: String(localized: "처음부터 다시"), cancel: { pending = nil }
                ) {
                    pending = nil
                    model.reset(all: false)
                }
            case .all:
                InlineConfirm(
                    message: String(localized: "모든 모드를 처음부터 다시 시작할까요? 만들어 둔 선수가 모두 사라집니다 (예전에 만든 구단 저장 파일도 함께 옮깁니다). 저장 파일은 지우지 않고 backups 폴더로 옮겨 둡니다."),
                    confirmTitle: String(localized: "전체 초기화"), cancel: { pending = nil }
                ) {
                    pending = nil
                    model.reset(all: true)
                }
            case nil:
                EmptyView()
            }
            Text("초기화한 뒤에는 처음 화면에서 새로 만듭니다. 예전 것은 저장 폴더의 backups 안에 날짜별로 남아 있어, 파일을 원래 자리로 옮기면 되살릴 수 있습니다.").note()
            Button("저장 폴더 열기") {
                NSWorkspace.shared.open(model.baseStore.fileURL.deletingLastPathComponent())
            }
        }
        .font(.callout)
    }
}
