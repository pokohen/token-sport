import Foundation

/// 저장 파일의 내용. 구단을 아직 만들지 않았으면 저장 파일 자체가 없다.
public struct GameSave: Codable, Equatable, Sendable {
    public static let currentVersion = 2

    public var version: Int
    public var game: Game

    public init(game: Game) {
        self.version = Self.currentVersion
        self.game = game
    }
}

/// 저장 칸: 종목과 모드마다 저장 파일을 따로 둔다. 한 번에 하나만 진행한다.
public enum SaveSlot: String, CaseIterable, Sendable {
    case baseball
    case football
    /// 야구 선수 모드.
    case baseballPlayer = "baseball-player"
    /// 축구 선수 모드.
    case footballPlayer = "football-player"
    /// 농구 선수 모드. (농구는 구단 모드가 없다.)
    case basketballPlayer = "basketball-player"

    public var sport: Sport {
        switch self {
        case .baseball, .baseballPlayer: .baseball
        case .football, .footballPlayer: .football
        case .basketballPlayer: .basketball
        }
    }
    /// 구단이 아니라 선수 한 명을 키우는 모드인지.
    public var isCareer: Bool {
        switch self {
        case .baseballPlayer, .footballPlayer, .basketballPlayer: true
        case .baseball, .football: false
        }
    }

    public var label: String {
        switch self {
        case .baseball: "야구 구단"
        case .football: "축구 구단"
        case .baseballPlayer: "야구 선수"
        case .footballPlayer: "축구 선수"
        case .basketballPlayer: "농구 선수"
        }
    }

    /// 그 종목의 구단 모드 칸. 농구는 구단 모드가 없어서 선수 모드 칸을 쓴다.
    public init(sport: Sport) {
        switch sport {
        case .baseball: self = .baseball
        case .football: self = .football
        case .basketball: self = .basketballPlayer
        }
    }

    /// 그 종목의 선수 모드 칸.
    public static func career(for sport: Sport) -> SaveSlot {
        switch sport {
        case .baseball: .baseballPlayer
        case .football: .footballPlayer
        case .basketball: .basketballPlayer
        }
    }
}

/// 게임 상태를 로컬 JSON 파일로 저장한다. 서버로 보내지 않는다.
public struct SaveStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL = SaveStore.defaultFileURL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/TokenBaseball/save.json`
    public static var defaultFileURL: URL {
        URL.applicationSupportDirectory
            .appendingPathComponent("TokenBaseball", isDirectory: true)
            .appendingPathComponent("save.json")
    }

    /// 같은 폴더에 있는 다른 종목의 저장 파일. 야구는 이 파일 그대로, 축구는 이름 뒤에 `-football`이 붙는다.
    /// (예: `save.json` → `save-football.json`)
    public func sibling(for sport: Sport) -> SaveStore { sibling(slot: SaveSlot(sport: sport)) }

    /// 같은 폴더에 있는 다른 저장 칸의 파일. 야구 구단은 이 파일 그대로, 나머지는 이름 뒤에 칸 이름이 붙는다.
    /// (예: `save.json` → `save-football.json`, `save-baseball-player.json`)
    public func sibling(slot: SaveSlot) -> SaveStore {
        guard slot != .baseball else { return self }
        let base = fileURL.deletingPathExtension().lastPathComponent
        let ext = fileURL.pathExtension
        let name = "\(base)-\(slot.rawValue)" + (ext.isEmpty ? "" : ".\(ext)")
        return SaveStore(fileURL: fileURL.deletingLastPathComponent().appendingPathComponent(name))
    }

    public var exists: Bool { FileManager.default.fileExists(atPath: fileURL.path) }

    /// 지금 운영 중인 종목을 적어 두는 파일 (`save.sport`). 없으면 야구다.
    var activeSportURL: URL { fileURL.deletingPathExtension().appendingPathExtension("sport") }

    public func loadActiveSport() -> Sport { loadActiveSlot().sport }

    public func saveActiveSport(_ sport: Sport) throws { try saveActiveSlot(SaveSlot(sport: sport)) }

    /// 지금 진행 중인 저장 칸. 같은 파일(`save.sport`)에 적고, 예전에 적어 둔 종목 이름도 그대로 읽힌다.
    public func loadActiveSlot() -> SaveSlot {
        guard let text = try? String(contentsOf: activeSportURL, encoding: .utf8) else { return .baseball }
        return SaveSlot(rawValue: text.trimmingCharacters(in: .whitespacesAndNewlines)) ?? .baseball
    }

    public func saveActiveSlot(_ slot: SaveSlot) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try slot.rawValue.write(to: activeSportURL, atomically: true, encoding: .utf8)
    }

    /// 초기화: 저장 파일을 지우지 않고 같은 폴더의 `backups/<이름>/`으로 옮긴다. 옮긴 곳을 돌려준다 (파일이 없으면 `nil`).
    /// 되돌리려면 그 파일을 원래 폴더로 다시 옮기면 된다.
    @discardableResult
    public func moveToBackup(named name: String) throws -> URL? {
        guard exists else { return nil }
        let folder = fileURL.deletingLastPathComponent()
            .appendingPathComponent("backups", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let target = folder.appendingPathComponent(fileURL.lastPathComponent)
        if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
        try FileManager.default.moveItem(at: fileURL, to: target)
        return target
    }

    /// 저장 파일이 없으면 `nil`. 파일이 깨졌으면 오류를 던진다 (조용히 새 게임으로 덮어쓰지 않기 위해).
    public func load() throws -> GameSave? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try Self.decoder.decode(GameSave.self, from: data)
    }

    public func save(_ save: GameSave) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        // 쓰는 도중 앱이 꺼져도 기존 파일이 깨지지 않게 통째로 바꿔 쓴다.
        try Self.encoder.encode(save).write(to: fileURL, options: .atomic)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        // 초 단위로 줄이지 않는다. 시각이 잘리면 같은 응답을 다시 셀 수 있다.
        encoder.dateEncodingStrategy = .deferredToDate
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }
}
