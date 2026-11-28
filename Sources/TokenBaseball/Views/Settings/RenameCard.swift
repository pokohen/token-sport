import SwiftUI
import TokenBaseballCore

/// 설정 탭: 내 선수(선수 모드)나 내 구단(구단 경영)의 이름을 바꾼다.
struct RenameCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var newName = ""

    var body: some View {
        if game.isCareer {
            if let me = game.myPlayer, game.career?.retired != true {
                Card(String(localized: "선수 이름")) {
                    field(placeholder: me.name) { try $0.renameCareerPlayer(to: $1) }
                    Text("12자까지. 지난 기록과 구단 이력은 그대로입니다.").note()
                }
            }
        } else {
            Card(String(localized: "팀 이름")) {
                field(placeholder: game.userTeam.name) { try $0.renameTeam($0.userTeamID, to: $1) }
            }
        }
    }

    private func field(placeholder: String, rename: @escaping (inout Game, String) throws -> Void) -> some View {
        HStack {
            TextField(placeholder, text: $newName).textFieldStyle(.roundedBorder)
            Button("바꾸기") {
                model.perform { try rename(&$0, newName) }
                if model.message == nil { newName = "" }
            }
            .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }
}
