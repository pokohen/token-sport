import AppKit
import SwiftUI
import TokenBaseballCore

/// 설정 탭: 지금 버전, 새 버전이 있는지, 업데이트하는 방법.
struct UpdateCard: View {
    @EnvironmentObject var model: AppModel
    @State private var copied = false
    @State private var showNotes = false

    private var game: Game? { model.game }

    private var commandRow: some View {
        HStack {
            Text(Self.command).font(.caption.monospaced()).textSelection(.enabled).lineLimit(2)
            Spacer()
            Button(copied ? "복사됨" : "명령 복사") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(Self.command, forType: .string)
                copied = true
            }
        }
    }

    /// 업데이트 명령. 배포 파일이나 설치 명령으로 설치했으면 설치 명령 한 줄을, 저장소를 직접 받아 만든 앱이면 업데이트 스크립트를 보여 준다.
    private static var command: String {
        let installed = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".token-sport/Scripts/install.sh")
        if UpdateChecker.isReleaseBuild || FileManager.default.fileExists(atPath: installed.path) {
            return UpdateChecker.installCommand
        }
        return "Scripts/update.sh"
    }

    var body: some View {
        Card(String(localized: "업데이트"), trailing: UpdateChecker.isReleaseBuild
            ? String(localized: "지금 \(UpdateChecker.appVersion)") : UpdateChecker.buildCommit.map { String(localized: "지금 \(String($0.prefix(7)))") }) {
            if let update = model.update {
                Label(update.headline, systemImage: "arrow.down.circle.fill")
                    .font(.callout.weight(.medium)).foregroundStyle(Color.accentColor)
                if !update.notes.isEmpty || !update.titles.isEmpty {
                    DisclosureGroup("업데이트 내용 (\(max(update.notes.count, update.titles.count))건)", isExpanded: $showNotes) {
                        VStack(alignment: .leading, spacing: 3) {
                            ForEach(Array((update.notes.isEmpty ? update.titles : update.notes).enumerated()), id: \.offset) { _, line in
                                Text("· \(line)").note().frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if let page = update.page {
                                Button("웹에서 자세히 보기") { NSWorkspace.shared.open(page) }.buttonStyle(.link).font(.caption)
                            }
                        }
                        .padding(.top, 4)
                    }
                }
                if update.download != nil, Updater.cachedBlockedReason == nil {
                    HStack {
                        Button(model.updateProgress ?? String(localized: "지금 업데이트")) { model.installUpdate() }
                            .buttonStyle(.borderedProminent)
                            .disabled(model.updateProgress != nil || game?.isMatchLive == true)
                        if model.updateProgress != nil { ProgressView().controlSize(.small) }
                    }
                    Text(game?.isMatchLive == true
                        ? "경기가 끝난 뒤에 업데이트할 수 있습니다."
                        : "새 버전을 내려받아 서명을 확인한 뒤, 앱이 잠깐 꺼졌다가 다시 열립니다. 선수는 그대로입니다.").note()
                    if let error = model.updateError {
                        Text(error).font(.caption).foregroundStyle(Theme.warn)
                        commandRow
                    }
                } else {
                    Text("터미널에서 아래 명령을 실행하면 새 버전으로 바뀝니다. 선수는 그대로입니다.").note()
                    commandRow
                }
            } else if let status = model.updateStatus {
                Text(status).font(.callout)
            } else {
                Text(UpdateChecker.isEnabled ? "아직 확인하지 않았습니다." : "자동 확인이 꺼져 있습니다.").font(.callout)
            }
            HStack {
                Toggle("새 버전 자동 확인", isOn: Binding(
                    get: { UpdateChecker.isEnabled },
                    set: { model.setUpdateCheckEnabled($0) }))
                Spacer()
                Button(model.checkingUpdate ? "확인하는 중…" : "지금 확인") { model.checkForUpdate(manual: true) }
                    .disabled(model.checkingUpdate)
            }
            Text("켜 두면 앱을 켤 때와 여섯 시간마다 GitHub에 새 변경이 있는지만 묻습니다. 보내는 것은 이 앱을 빌드한 버전(커밋)뿐이고, 토큰 사용량과 게임 내용은 보내지 않습니다.").note()
        }
        .font(.callout)
    }
}
