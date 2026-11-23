import AppKit
import Foundation
import SwiftUI
import TokenBaseballCore

/// 앱 상태: 게임을 들고 있고, 토큰을 읽고, 경기를 한 구씩 진행하고, 저장한다.
@MainActor
final class AppModel: ObservableObject {
    @Published var game: Game?
    @Published var todayTokens = 0
    @Published var now = Date()
    @Published var message: String?
    @Published var loadError: String?
    /// 상단바 훈련 애니메이션 프레임.
    @Published var frame = 0
    /// 최근에 토큰을 쓴 시각 (쉬는 모습으로 바꿀지 판단).
    @Published var lastTokenAt: Date?
    @Published var recentRate = 0

    /// 야구 저장 파일의 위치. 축구 저장 파일은 같은 폴더에 따로 둔다.
    let baseStore: SaveStore
    /// 지금 진행 중인 저장 칸 (야구 구단 / 축구 구단 / 야구 선수).
    @Published var slot: SaveSlot
    /// 지금 종목.
    var sport: Sport { slot.sport }
    /// 지금 저장 칸의 파일.
    var store: SaveStore { baseStore.sibling(slot: slot) }
    let sources: UsageSources
    var matchGeneration = 0
    var matchTask: Task<Void, Never>?
    var pendingSave: Task<Void, Never>?
    var timers: [Timer] = []
    var pitchesSinceSave = 0
    /// 직전에 경기를 치를 수 있는 상태였는지. 앱을 켠 직후에는 아직 모른다 (nil).
    var wasMatchReady: Bool?
    /// 팝오버가 열려 있는지. 열려 있을 때 끝난 경기는 바로 확인한 것으로 본다.
    var popoverVisible = false
    let launchedAt = Date()

    /// 새 버전이 있으면 그 내용. 없거나 아직 확인하지 않았으면 nil.
    @Published var update: UpdateChecker.Update?
    /// 마지막 업데이트 확인의 결과를 한 줄로 (설정 탭에 보인다).
    @Published var updateStatus: String?
    @Published var checkingUpdate = false
    /// 앱 안에서 업데이트하는 중이면 지금 하는 일 ("내려받는 중…").
    @Published var updateProgress: String?
    /// 앱 안 업데이트가 실패한 이유.
    @Published var updateError: String?

    /// 고를 수 있는 모드. 구단 경영(야구 구단, 축구 구단)은 코드는 남아 있지만 앱에서는 뺐다.
    let selectableSlots: [SaveSlot] = [.baseballPlayer, .footballPlayer, .basketballPlayer]

    /// 공 하나에 걸리는 시간 (1배속 기준).
    static let pitchInterval: Duration = .seconds(3)
    /// 고를 수 있는 중계 배속.
    static let matchSpeeds = [1, 2, 4, 8]
    /// 중계 배속. 경기 도중에도 바꿀 수 있고, 다음 경기에도 이어진다.
    @Published var matchSpeed: Int = {
        let saved = UserDefaults.standard.integer(forKey: "matchSpeed")
        return AppModel.matchSpeeds.contains(saved) ? saved : 1
    }() {
        didSet { UserDefaults.standard.set(matchSpeed, forKey: "matchSpeed") }
    }

    init(store: SaveStore = AppModel.defaultStore(), sources: UsageSources = UsageSources()) {
        self.baseStore = store
        self.sources = sources
        let saved = store.loadActiveSlot()
        // 예전에 구단 경영을 하던 채로 껐으면 선수 모드로 연다. 구단 저장 파일은 그대로 둔다.
        self.slot = saved.isCareer ? saved : .baseballPlayer
        loadGame()
        if !saved.isCareer {
            try? store.saveActiveSlot(slot)
            // 쉬고 있던 선수는 그동안 쓴 토큰과 흐른 시간을 받지 않는다 (모드를 바꿀 때와 같다).
            if game != nil {
                game?.resume(now: Date())
                save()
            }
        }
    }

    func loadGame() {
        loadError = nil
        do {
            game = try store.load()?.game
        } catch {
            game = nil
            loadError = "저장 파일을 읽지 못했습니다.\n\(store.fileURL.path)\n\(error.localizedDescription)"
        }
    }

    /// `TOKEN_BASEBALL_SAVE` 환경 변수로 저장 위치를 바꿀 수 있다 (개발·확인용).
    static func defaultStore() -> SaveStore {
        if let path = ProcessInfo.processInfo.environment["TOKEN_BASEBALL_SAVE"], !path.isEmpty {
            return SaveStore(fileURL: URL(fileURLWithPath: path))
        }
        return SaveStore()
    }

    func start() {
        guard timers.isEmpty else { return }
        timers.append(Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.everySecond() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 20, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.pollUsage() }
        })
        // 새 버전 확인: 켤 때 한 번, 그 뒤로 여섯 시간마다.
        timers.append(Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkForUpdate() }
        })
        checkForUpdate()
        scheduleAnimation()
        pollUsage()
        if game?.isMatchLive == true { runMatchLoop() }
        Notifier.requestPermission()
        // 앱이 꺼질 때 마지막 상태를 저장한다.
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.save() }
        }
    }

    func everySecond() {
        now = Date()
        guard game != nil else { return }
        game?.refreshCharges(now: now)
        // 경기 기회가 새로 생겼을 때만 알린다. 앱을 켤 때마다, 또는 기회가 남은 채로 경기가 끝날 때마다 알리지 않는다.
        // 그래서 경기 중에는 비교하지 않고, 경기 전의 상태와 견준다.
        if game?.isMatchLive != true {
            let ready = (game?.charges ?? 0) > 0 && game?.nextMatch() != nil
            if ready, wasMatchReady == false { notify("경기를 치를 수 있습니다", "상단바를 눌러 경기를 시작하세요.") }
            wasMatchReady = ready
        }
        updateStatusTooltip()
    }

    func save() {
        guard let game else { return }
        do {
            try store.save(GameSave(game: game))
        } catch {
            message = "저장하지 못했습니다: \(error.localizedDescription)"
        }
    }

    /// 잠깐 모았다가 저장한다. 슬라이더처럼 연달아 바뀌는 값마다 파일을 쓰지 않기 위해서다.
    func saveSoon() {
        pendingSave?.cancel()
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    /// 게임 상태를 바꾸는 명령을 실행하고 저장한다. 실패하면 이유를 보여준다.
    func perform(_ action: (inout Game) throws -> Void) {
        guard var copy = game else { return }
        do {
            try action(&copy)
            game = copy
            message = nil
            saveSoon()
        } catch let error as GameError {
            message = error.message
        } catch {
            message = error.localizedDescription
        }
    }
}
