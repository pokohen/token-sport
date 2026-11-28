import Foundation
import Security

/// 앱 안에서 새 버전으로 바꾼다 (배포 파일로 설치한 앱만).
///
/// 순서: 배포 파일(.dmg)을 내려받는다 → 연다 → 안의 앱을 꺼낸다 → **이 앱과 같은 개발자가 서명했고
/// Apple 공증을 받았는지 검사한다** → 이 앱이 꺼진 뒤 자리를 바꾸고 다시 여는 작은 스크립트를 띄운다.
/// 검사에서 하나라도 어긋나면 아무것도 바꾸지 않는다. 저장 파일은 건드리지 않는다.
enum Updater {
    struct Failure: Error, Equatable {
        var message: String
        init(_ message: String) { self.message = message }
    }

    static let appName = "Token Sports.app"
    /// 0.7.1까지 쓰던 번들 이름. 예전 배포 파일 안에는 앱이 이 이름으로 들어 있다.
    static let legacyAppName = "Token Baseball.app"

    /// 지금 실행 중인 앱 번들. 번들 없이 실행했으면 nil.
    static var installedApp: URL? {
        let url = Bundle.main.bundleURL
        return url.pathExtension == "app" ? url : nil
    }

    /// `blockedReason()`을 한 번만 계산해 둔 값. 서명을 디스크에서 읽으므로 화면을 그릴 때마다 부르지 않는다.
    /// (실행 중에는 앱 번들의 위치와 서명이 바뀌지 않는다.)
    static let cachedBlockedReason: String? = blockedReason()

    /// 앱 안에서 업데이트할 수 없는 이유. 할 수 있으면 nil.
    static func blockedReason(app: URL? = installedApp) -> String? {
        guard UpdateChecker.isReleaseBuild, let app else { return String(localized: "배포 파일로 설치한 앱에서만 됩니다.") }
        if app.path.contains("/AppTranslocation/") {
            return String(localized: "앱을 응용 프로그램 폴더로 옮긴 뒤에 할 수 있습니다.")
        }
        if !FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) {
            return String(localized: "앱이 있는 폴더를 고칠 권한이 없습니다. 아래 명령으로 업데이트하세요.")
        }
        if teamIdentifier(of: app) == nil { return String(localized: "서명되지 않은 앱이라 앱 안에서 업데이트할 수 없습니다.") }
        return nil
    }

    /// 서명한 개발자 팀 ID. 서명이 없거나 깨졌으면 nil.
    static func teamIdentifier(of app: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return nil }
        var info: CFDictionary?
        guard SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess,
              let dictionary = info as? [String: Any] else { return nil }
        return dictionary[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// 서명이 온전하고, 그 팀의 Developer ID로 서명됐는지.
    static func isSigned(_ app: URL, byTeam team: String) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(app as CFURL, [], &code) == errSecSuccess, let code else { return false }
        let text = "anchor apple generic and certificate leaf[subject.OU] = \"\(team)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(text as CFString, [], &requirement) == errSecSuccess else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// 명령을 실행하고 (종료 코드, 출력)을 돌려준다.
    @discardableResult
    static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do { try process.run() } catch { return (-1, error.localizedDescription) }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    /// 배포 파일을 내려받아 검사까지 마친 새 앱을 임시 폴더에 준비한다. 돌려주는 것은 그 앱의 위치.
    static func prepare(
        from download: URL, expectedVersion: String, current app: URL, progress: @Sendable (String) -> Void
    ) async throws -> URL {
        guard download.scheme == "https" || download.isFileURL else { throw Failure(String(localized: "내려받는 주소가 올바르지 않습니다.")) }
        guard let team = teamIdentifier(of: app) else { throw Failure(String(localized: "이 앱의 서명을 읽지 못했습니다.")) }
        let work = FileManager.default.temporaryDirectory
            .appendingPathComponent("TokenSportUpdate-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        do {
            progress(String(localized: "내려받는 중…"))
            let image = work.appendingPathComponent("update.dmg")
            if download.isFileURL {
                try FileManager.default.copyItem(at: download, to: image)
            } else {
                var request = URLRequest(url: download, timeoutInterval: 120)
                request.setValue("TokenSport-update", forHTTPHeaderField: "User-Agent")
                let (file, response) = try await URLSession.shared.download(for: request)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Failure(String(localized: "내려받지 못했습니다.")) }
                try FileManager.default.moveItem(at: file, to: image)
            }

            progress(String(localized: "확인하는 중…"))
            let mount = work.appendingPathComponent("mnt", isDirectory: true)
            guard run("/usr/bin/hdiutil", ["attach", image.path, "-nobrowse", "-readonly", "-quiet", "-mountpoint", mount.path]).status == 0 else {
                throw Failure(String(localized: "내려받은 파일을 열지 못했습니다."))
            }
            let fresh = work.appendingPathComponent(appName, isDirectory: true)
            let inside = [appName, legacyAppName].map { mount.appendingPathComponent($0) }
                .first { FileManager.default.fileExists(atPath: $0.path) }
            let copied = inside.map { run("/usr/bin/ditto", [$0.path, fresh.path]).status == 0 } ?? false
            run("/usr/bin/hdiutil", ["detach", mount.path, "-quiet", "-force"])
            guard copied else { throw Failure(String(localized: "내려받은 파일 안에 앱이 없습니다.")) }

            // 같은 개발자가 서명했는가, Apple 공증을 받았는가, 정말 그 버전인가.
            guard isSigned(fresh, byTeam: team) else { throw Failure(String(localized: "새 버전의 서명이 이 앱과 다릅니다. 업데이트하지 않았습니다.")) }
            guard run("/usr/sbin/spctl", ["--assess", "--type", "execute", fresh.path]).status == 0 else {
                throw Failure(String(localized: "새 버전이 Apple 공증 검사를 통과하지 못했습니다. 업데이트하지 않았습니다."))
            }
            let plist = NSDictionary(contentsOf: fresh.appendingPathComponent("Contents/Info.plist"))
            guard plist?["CFBundleShortVersionString"] as? String == expectedVersion else {
                throw Failure(String(localized: "내려받은 앱의 버전이 다릅니다. 업데이트하지 않았습니다."))
            }
            return fresh
        } catch {
            try? FileManager.default.removeItem(at: work)
            throw error
        }
    }

    /// 새 앱을 놓을 자리. 예전 이름("Token Baseball.app")으로 설치돼 있으면 같은 폴더에 새 이름으로 놓는다.
    static func destination(for app: URL) -> URL {
        app.lastPathComponent == legacyAppName
            ? app.deletingLastPathComponent().appendingPathComponent(appName, isDirectory: true) : app
    }

    /// 이 앱이 꺼지면 새 앱으로 자리를 바꾸고 다시 여는 스크립트를 띄운다. 띄운 뒤 곧바로 앱을 꺼야 한다.
    /// 바꾸다 실패하면 예전 앱을 되돌려 놓는다. 예전 이름으로 설치된 앱은 이때 새 이름으로 바뀐다.
    static func swapAfterExit(
        fresh: URL, into app: URL, reopen: Bool, waitingFor pid: Int32 = ProcessInfo.processInfo.processIdentifier
    ) throws {
        // 어느 단계에서 실패하든: 받아 둔 파일을 지우고, 자리에 남아 있는 앱(예전 것이든 새것이든)을 다시 연다.
        let script = """
        pid="$1"; fresh="$2"; app="$3"; reopen="$4"; dest="$5"
        finish() {
            rm -rf "$(dirname "$fresh")"
            if [ "$reopen" = "1" ]; then
                if [ -d "$dest" ]; then /usr/bin/open "$dest"; elif [ -d "$app" ]; then /usr/bin/open "$app"; fi
            fi
            exit 0
        }
        n=0; while kill -0 "$pid" 2>/dev/null && [ $n -lt 150 ]; do sleep 0.2; n=$((n+1)); done
        # 앱이 끝내 꺼지지 않았으면 실행 중인 앱을 건드리지 않는다.
        if kill -0 "$pid" 2>/dev/null; then rm -rf "$(dirname "$fresh")"; exit 0; fi
        old="$app.old-$$"
        mv "$app" "$old" || finish
        # 이름이 바뀌는 경우: 새 이름의 자리에 이미 무엇이 있으면 치운다.
        [ "$dest" != "$app" ] && rm -rf "$dest"
        if /usr/bin/ditto "$fresh" "$dest"; then rm -rf "$old"; else rm -rf "$dest"; mv "$old" "$app"; fi
        finish
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        // 한 번 더 띄워서(&) 이 앱이 꺼져도 남아 있게 한다.
        process.arguments = [
            "-c", "/bin/sh -c \"$0\" sh \"$@\" >/dev/null 2>&1 &", script,
            String(pid), fresh.path, app.path, reopen ? "1" : "0",
            destination(for: app).path,
        ]
        try process.run()
        process.waitUntilExit()
    }
}
