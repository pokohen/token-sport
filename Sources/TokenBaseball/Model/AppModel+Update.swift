import AppKit
import Foundation
import TokenBaseballCore

/// 새 버전 확인과 알림.
extension AppModel {
    /// 새 버전이 있는지 확인한다. `manual`이면 설정에서 꺼 두었어도 확인한다.
    func checkForUpdate(manual: Bool = false) {
        guard manual || UpdateChecker.isEnabled, !checkingUpdate else { return }
        // 번들 없이 실행한 개발 빌드는 조용히 넘어간다.
        guard manual || UpdateChecker.buildCommit != nil || UpdateChecker.isReleaseBuild else { return }
        checkingUpdate = true
        Task { [weak self] in
            let outcome = await UpdateChecker.check()
            self?.apply(outcome)
        }
    }

    func apply(_ outcome: UpdateChecker.Outcome) {
        checkingUpdate = false
        switch outcome {
        case .upToDate:
            update = nil
            updateStatus = String(localized: "최신 버전입니다.")
        case .available(let found):
            update = found
            updateStatus = found.headline + "."
            // 같은 업데이트는 한 번만 알린다.
            if UpdateChecker.notifiedHead != found.head {
                UpdateChecker.notifiedHead = found.head
                if game?.settings.notificationsEnabled ?? true {
                    Notifier.send(
                        title: String(localized: "Token Sports 새 버전"),
                        body: (found.titles.first ?? String(localized: "변경 \(found.count)건")) + String(localized: " — 설정 탭에서 업데이트 방법을 확인하세요"))
                }
            }
        case .unknown(let reason):
            updateStatus = reason
        }
    }

    func setUpdateCheckEnabled(_ enabled: Bool) {
        UpdateChecker.isEnabled = enabled
        objectWillChange.send()
        if enabled { checkForUpdate() } else { update = nil; updateStatus = nil }
    }

    /// 앱 안에서 새 버전으로 바꾼다: 내려받고, 서명과 공증을 검사하고, 앱을 끄고 바꾼 뒤 다시 연다.
    func installUpdate() {
        guard updateProgress == nil, let update, let version = update.version, let download = update.download,
              let app = Updater.installedApp else { return }
        if let reason = Updater.blockedReason() { updateError = reason; return }
        updateError = nil
        updateProgress = String(localized: "내려받는 중…")
        Task { [weak self] in
            do {
                let fresh = try await Updater.prepare(from: download, expectedVersion: version, current: app) { text in
                    Task { @MainActor in self?.updateProgress = text }
                }
                guard let self else { return }
                self.updateProgress = String(localized: "다시 여는 중…")
                self.pendingSave?.cancel()
                self.save()
                do {
                    try Updater.swapAfterExit(fresh: fresh, into: app, reopen: true)
                } catch {
                    try? FileManager.default.removeItem(at: fresh.deletingLastPathComponent())
                    throw error
                }
                NSApplication.shared.terminate(nil)
            } catch {
                self?.updateProgress = nil
                self?.updateError = (error as? Updater.Failure)?.message ?? String(localized: "업데이트하지 못했습니다: \(error.localizedDescription)")
            }
        }
    }
}
