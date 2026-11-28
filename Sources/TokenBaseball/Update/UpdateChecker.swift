import Foundation

/// 새 버전이 나왔는지 알아본다.
///
/// 배포 파일로 설치한 앱은 최신 배포 버전과, 소스로 직접 만든 앱은 빌드한 시점의 커밋과 비교한다.
/// `Scripts/make-app.sh`가 앱 번들에 그 커밋과 저장소 이름을 적어 두고,
/// 앱은 GitHub에 "이 커밋 뒤로 기본 브랜치에 몇 개가 더 쌓였는지"만 묻는다.
///
/// 이것이 이 앱이 하는 유일한 네트워크 요청이다. 보내는 것은 저장소 이름과 빌드 커밋뿐이고,
/// 토큰 사용량이나 게임 내용은 보내지 않는다. 설정에서 끌 수 있다.
enum UpdateChecker {
    struct Update: Equatable, Sendable {
        /// 지금 빌드보다 앞선 변경 수.
        var count: Int
        /// 가장 최근 변경의 제목들 (새 것부터, 병합 기록은 뺀다).
        var titles: [String]
        /// 기본 브랜치의 맨 끝 커밋(또는 배포 버전). 같은 업데이트를 두 번 알리지 않으려고 쓴다.
        var head: String
        /// 배포 버전이면 그 이름 (예: "0.3.0")과 내려받는 페이지.
        var version: String? = nil
        var page: URL? = nil
        /// 배포 파일(.dmg)을 내려받는 주소. 앱 안에서 업데이트할 때 쓴다.
        var download: URL? = nil
        /// 변경 내용 전체 (titles는 앞의 몇 줄만).
        var notes: [String] = []

        /// 화면에 보이는 한 줄 제목.
        var headline: String {
            version.map { String(localized: "새 버전 \($0)이(가) 나왔습니다") } ?? String(localized: "새 버전이 있습니다 (변경 \(count)건)")
        }
    }

    enum Outcome: Equatable, Sendable {
        case upToDate
        case available(Update)
        /// 확인하지 못했다 (오프라인, 직접 고친 빌드 등). 이유를 담는다.
        case unknown(String)
    }

    /// 빌드한 커밋. 번들 없이 실행하면(`swift run`) 알 수 없다.
    static var buildCommit: String? {
        if let value = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_BUILD_COMMIT"], !value.isEmpty { return value }
        return (Bundle.main.object(forInfoDictionaryKey: "TBCommit") as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `소유자/저장소`.
    static var repository: String {
        (Bundle.main.object(forInfoDictionaryKey: "TBRepository") as? String).flatMap { $0.isEmpty ? nil : $0 }
            ?? "pokohen/token-sport"
    }

    static var isEnabled: Bool {
        get { !UserDefaults.standard.bool(forKey: "updateCheckDisabled") }
        set { UserDefaults.standard.set(!newValue, forKey: "updateCheckDisabled") }
    }

    /// 이미 알린 업데이트의 맨 끝 커밋.
    static var notifiedHead: String? {
        get { UserDefaults.standard.string(forKey: "updateNotifiedHead") }
        set { UserDefaults.standard.set(newValue, forKey: "updateNotifiedHead") }
    }

    /// 배포 파일(.dmg)로 설치한 앱인지. 그러면 새 버전은 "최신 배포 버전"과 비교한다.
    static var isReleaseBuild: Bool {
        if ProcessInfo.processInfo.environment["TOKEN_BASEBALL_RELEASE_VERSION"] != nil { return true }
        return Bundle.main.object(forInfoDictionaryKey: "TBRelease") as? Bool ?? false
    }

    /// 이 앱의 버전 (예: "0.2.0").
    static var appVersion: String {
        ProcessInfo.processInfo.environment["TOKEN_BASEBALL_RELEASE_VERSION"]
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// 설치·업데이트 명령 한 줄.
    static var installCommand: String {
        "curl -fsSL https://raw.githubusercontent.com/\(repository)/main/Scripts/install.sh | bash"
    }

    static func check() async -> Outcome {
        if isReleaseBuild {
            // 배포 버전 확인: GitHub Releases의 최신 버전이 이 앱보다 높은지. 올라온 배포가 없으면(404) 최신이다.
            return await fetch("releases/latest", notFound: .upToDate) { parseRelease($0, current: appVersion) }
        }
        guard let commit = buildCommit else {
            return .unknown(String(localized: "앱 번들로 실행할 때만 확인할 수 있습니다 (Scripts/make-app.sh로 만든 앱)."))
        }
        return await fetch(
            "compare/\(commit)...HEAD", notFound: .unknown(String(localized: "이 빌드의 커밋이 저장소에 없습니다 (직접 고친 빌드).")), parse: parse)
    }

    /// GitHub API에 한 번 묻고 응답을 읽는다.
    private static func fetch(_ path: String, notFound: Outcome, parse: (Data) -> Outcome) async -> Outcome {
        guard let url = URL(string: "https://api.github.com/repos/\(repository)/\(path)") else {
            return .unknown(String(localized: "저장소 주소가 올바르지 않습니다."))
        }
        var request = URLRequest(url: url, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("TokenSport-update-check", forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 404 { return notFound }
            guard status == 200 else { return .unknown(String(localized: "GitHub가 응답하지 않았습니다 (\(status)).")) }
            return parse(data)
        } catch {
            return .unknown(String(localized: "확인하지 못했습니다: \(error.localizedDescription)"))
        }
    }

    /// GitHub의 최신 배포 응답을 읽어 지금 버전과 비교한다.
    static func parseRelease(_ data: Data, current: String) -> Outcome {
        struct Response: Decodable {
            let tag_name: String
            let name: String?
            let body: String?
            let html_url: String?
            struct Asset: Decodable { let name: String; let browser_download_url: String }
            let assets: [Asset]?
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return .unknown(String(localized: "응답을 읽지 못했습니다."))
        }
        let latest = response.tag_name.hasPrefix("v") ? String(response.tag_name.dropFirst()) : response.tag_name
        guard isVersion(latest, newerThan: current) else { return .upToDate }
        // 배포 설명의 목록 줄을 변경 내용으로 보여 준다.
        let notes = (response.body ?? "").split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("* ") || $0.hasPrefix("- ") }
            .map { cleanNote(String($0.dropFirst(2))) }
        let download = response.assets?.first { $0.name.hasSuffix(".dmg") }
            .flatMap { URL(string: $0.browser_download_url) }
        return .available(Update(
            count: max(1, notes.count), titles: Array(notes.prefix(5)), head: response.tag_name,
            version: latest, page: response.html_url.flatMap(URL.init(string:)),
            download: download, notes: notes))
    }

    /// GitHub가 자동으로 적은 줄("제목 by @누구 in https://…/pull/3")에서 제목만 남긴다.
    static func cleanNote(_ line: String) -> String {
        guard let range = line.range(of: " by @", options: .backwards), line[range.upperBound...].contains(" in https://") else {
            return line
        }
        return String(line[..<range.lowerBound])
    }

    /// "0.10.0" > "0.9.3" 같은 숫자 비교.
    static func isVersion(_ a: String, newerThan b: String) -> Bool {
        let x = a.split(separator: ".").map { Int($0) ?? 0 }
        let y = b.split(separator: ".").map { Int($0) ?? 0 }
        for index in 0..<max(x.count, y.count) {
            let l = index < x.count ? x[index] : 0, r = index < y.count ? y[index] : 0
            if l != r { return l > r }
        }
        return false
    }

    /// GitHub의 compare 응답을 읽는다.
    static func parse(_ data: Data) -> Outcome {
        struct Response: Decodable {
            struct Entry: Decodable {
                struct Detail: Decodable { let message: String }
                let sha: String
                let commit: Detail
            }
            let ahead_by: Int
            let commits: [Entry]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            return .unknown(String(localized: "응답을 읽지 못했습니다."))
        }
        guard response.ahead_by > 0, let head = response.commits.last?.sha else { return .upToDate }
        let titles = response.commits.reversed()
            .map { String($0.commit.message.split(separator: "\n").first ?? "") }
            .filter { !$0.hasPrefix("Merge ") && !$0.isEmpty }
        return .available(Update(count: response.ahead_by, titles: Array(titles.prefix(5)), head: head))
    }
}
