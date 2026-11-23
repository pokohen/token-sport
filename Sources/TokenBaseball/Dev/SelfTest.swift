import Foundation
import TokenBaseballCore

/// 앱 흐름 자가 점검 (`TOKEN_BASEBALL_SELFTEST=빈 폴더`).
/// 화면 없이 앱 상태(AppModel)를 직접 몰아서, 만들기 → 훈련 → 경기 → 모드 전환 → 다시 켜기가
/// 실제 저장 파일과 함께 돌아가는지 본다. 진짜 저장 파일은 건드리지 않는다.
@MainActor
enum SelfTest {
    static func run(in directory: URL) -> Bool {
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let store = SaveStore(fileURL: directory.appendingPathComponent("save.json"))
        var failures = 0
        func check(_ name: String, _ ok: Bool, _ detail: @autoclosure () -> String = "") {
            print("\(ok ? "PASS" : "FAIL") \(name)\(ok ? "" : " — \(detail())")")
            if !ok { failures += 1 }
        }
        func exists(_ name: String) -> Bool {
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(name).path)
        }
        /// 토큰을 쓴 것처럼 넣고, 경기 한 번을 끝까지 치른다. 경기 기회가 다시 생기도록 부를 때마다 한 시간씩 흐른다.
        var hours = 0.0
        func playOne(_ model: AppModel, label: String) {
            hours += 1.5
            let now = Date().addingTimeInterval(hours * 3600)
            _ = model.game?.collect(
                [UsageRecord(id: "selftest-\(label)-\(now.timeIntervalSince1970)", timestamp: now, usage: TokenUsage(output: 20_000_000))],
                now: now)
            model.perform { try $0.startMatch(now: now) }
            check("\(label): 경기 시작", model.game?.isMatchLive == true, model.message ?? "경기가 열리지 않음")
            model.game?.runMatchToEnd()
            check("\(label): 경기 종료", model.game?.isMatchLive == false && model.game?.lastResult != nil)
            model.save()
        }

        // 1. 처음 켰을 때
        var model = AppModel(store: store, sources: UsageSources())
        check("처음: 게임 없음", model.game == nil && model.slot == .baseballPlayer)

        // 2. 축구 선수 만들기 → 훈련 → 스타일 → 경기
        model.createCareer(CareerSetup(name: "점검 공격수", position: .forward, hometown: "부산"))
        check("축구 선수: 만들어짐", model.game?.myPlayer?.name == "점검 공격수", model.message ?? "")
        check("축구 선수: 칸", model.slot == .footballPlayer && exists("save-football-player.json"))
        check("축구 선수: 종목", model.game?.sport == .football && model.sport == .football)
        playOne(model, label: "축구 선수 1")
        if let key = model.game?.careerTrainableKeys.first {
            let before = model.game?.myPlayer?.ability ?? 0
            model.perform { try $0.trainCareer(key) }
            check("축구 선수: 훈련", (model.game?.myPlayer?.ability ?? 0) > before, model.message ?? "")
        }
        model.perform { $0.setCareerStyle(.greedy) }
        check("축구 선수: 스타일", model.game?.career?.style == .greedy)
        playOne(model, label: "축구 선수 2")
        check("축구 선수: 평점 또는 미출전 기록", model.game?.lastResult?.summary.isEmpty == false)
        // 스카우트: 붙이고, 저장했다가 다시 읽어도 남아 있다
        model.perform { $0.generateDemoCareerScouts() }
        let scoutCount = model.game?.careerScouts.count ?? 0
        model.save()
        let reloaded = (try? model.store.load())?.game
        check("축구 선수: 스카우트가 저장된다", scoutCount > 0 && reloaded?.careerScouts.count == scoutCount)

        // 2-1. 농구 선수 만들기 → 훈련 → 경기 (다른 칸에서 바로)
        model.createCareer(CareerSetup(
            name: "점검 가드", position: .pointGuard, hometown: "대구", points: [.passing: 2, .dribbling: 2, .three: 1]))
        check("농구 선수: 만들어짐", model.game?.myPlayer?.name == "점검 가드", model.message ?? "")
        check("농구 선수: 칸", model.slot == .basketballPlayer && exists("save-basketball-player.json"))
        check("농구 선수: 종목", model.game?.sport == .basketball && model.sport == .basketball)
        check("농구 선수: 세계", model.game?.teams.count == 60
            && model.game?.players.values.allSatisfy { $0.position.sport == .basketball } == true)
        playOne(model, label: "농구 선수 1")
        if let key = model.game?.careerTrainableKeys.first {
            let before = model.game?.myPlayer?.ability ?? 0
            model.perform { try $0.trainCareer(key) }
            check("농구 선수: 훈련", (model.game?.myPlayer?.ability ?? 0) > before, model.message ?? "")
        }
        model.perform { $0.setCareerStyle(.link) }
        playOne(model, label: "농구 선수 2")
        check("농구 선수: 기록", (model.game?.myPlayer?.basketball?.games ?? 0) == 2
            && model.game?.career?.lastRating != nil)
        check("축구 선수 저장은 그대로", exists("save-football-player.json"))

        // 3. 야구 구단으로 전환 (없음 → 창단)
        model.switchSlot(to: .baseball)
        check("야구 구단: 전환하면 창단 화면", model.game == nil && model.slot == .baseball, model.message ?? "")
        model.createClub(.init(city: "서울", name: "점검 야구단"), sport: .baseball)
        check("야구 구단: 창단", model.game?.userTeam.name == "점검 야구단" && model.game?.isCareer == false, model.message ?? "")
        check("야구 구단: 파일", exists("save.json"))
        playOne(model, label: "야구 구단")

        // 4. 야구 선수 만들기 (다른 칸에서 바로)
        model.createCareer(CareerSetup(name: "점검 투수", position: .starter, bats: .left, throwsHand: .left))
        check("야구 선수: 만들어짐", model.game?.myPlayer?.name == "점검 투수" && model.slot == .baseballPlayer, model.message ?? "")
        check("야구 선수: 파일", exists("save-baseball-player.json"))
        playOne(model, label: "야구 선수")
        if let key = model.game?.careerTrainableKeys.first {
            model.perform { try $0.trainCareer(key) }
            check("야구 선수: 훈련", model.message == nil, model.message ?? "")
        }
        model.save()

        // 5. 축구 구단 창단 (다른 칸에서 바로)
        model.createClub(.init(city: "대전", name: "점검 FC"), sport: .football)
        check("축구 구단: 창단", model.game?.userTeam.name == "점검 FC" && model.slot == .football, model.message ?? "")
        check("축구 구단: 파일", exists("save-football.json"))
        playOne(model, label: "축구 구단")

        // 6. 칸을 오가도 그대로
        model.switchSlot(to: .footballPlayer)
        check("돌아옴: 축구 선수", model.game?.myPlayer?.name == "점검 공격수" && model.game?.career?.style == .greedy)
        model.switchSlot(to: .baseball)
        check("돌아옴: 야구 구단", model.game?.userTeam.name == "점검 야구단")
        model.switchSlot(to: .baseballPlayer)
        check("돌아옴: 야구 선수", model.game?.myPlayer?.name == "점검 투수")
        // 이미 있는 선수를 덮어쓰지 않는다
        model.createCareer(CareerSetup(name: "덮어쓰기", position: .catcher))
        check("덮어쓰지 않음", model.game?.myPlayer?.name == "점검 투수")

        // 7. 앱을 껐다 켰을 때
        model.save()
        model = AppModel(store: store, sources: UsageSources())
        check("다시 켬: 마지막 칸", model.slot == .baseballPlayer && model.game?.myPlayer?.name == "점검 투수", model.loadError ?? "")
        check("다시 켬: 오류 없음", model.loadError == nil, model.loadError ?? "")
        // 구단 경영을 하던 채로 껐어도 선수 모드로 열리고, 구단 저장 파일은 남는다
        try? store.saveActiveSlot(.football)
        model = AppModel(store: store, sources: UsageSources())
        check("구단 모드로 껐어도 선수 모드로 연다", model.slot == .baseballPlayer && model.game?.myPlayer?.name == "점검 투수")
        check("구단 저장 파일은 그대로", exists("save-football.json") && exists("save.json"))
        check("고를 수 있는 모드는 선수 셋", model.selectableSlots == [.baseballPlayer, .footballPlayer, .basketballPlayer])

        // 8. 경기 도중에 껐다 켰을 때
        model.switchSlot(to: .footballPlayer)
        model.perform { try $0.startMatch(now: Date().addingTimeInterval((hours + 4) * 3600)) }
        for _ in 0..<60 { model.game?.stepMatch() }
        model.save()
        model = AppModel(store: store, sources: UsageSources())
        check("경기 중 다시 켬", model.game?.isMatchLive == true && model.slot == .footballPlayer, model.loadError ?? "")
        model.game?.runMatchToEnd()
        check("이어서 끝까지", model.game?.isMatchLive == false)

        // 추가 경기: 기회가 없을 때 토큰으로 사서 바로 시작한다
        // 같은 시각에 남은 기회를 다 써서 기회가 없는 상태를 만든다.
        let fixed = Date().addingTimeInterval((hours + 4) * 3600)
        var spent = 0
        while (model.game?.charges ?? 0) > 0, spent < 5 {
            model.perform { try $0.startMatch(now: fixed) }
            model.game?.runMatchToEnd()
            spent += 1
        }
        check("추가 경기: 기회가 없는 상태", model.game?.charges == 0)
        _ = model.game?.collect(
            [UsageRecord(id: "selftest-extra", timestamp: Date(), usage: TokenUsage(output: 30_000_000))], now: Date())
        model.buyExtraMatchAndStart()
        check("추가 경기: 사서 바로 시작", model.game?.isMatchLive == true, model.message ?? "")
        // 결과 바로 보기: 중계가 도는 중에 눌러도 경기가 끝나고 값이 빠진다
        let beforeSkip = model.game?.funds.seasonExpense[FundsLedger.Category.skipMatch.rawValue] ?? 0
        model.skipMatch()
        check("결과 바로 보기: 경기 끝", model.game?.isMatchLive == false && model.game?.lastResult != nil, model.message ?? "")
        check("결과 바로 보기: 값 냄",
              (model.game?.funds.seasonExpense[FundsLedger.Category.skipMatch.rawValue] ?? 0) - beforeSkip
                  == model.game?.skipMatchCost)
        check("추가 경기: 값이 두 배", model.game?.extraMatchCost == Balance.extraMatchCost * 2)
        // 배속은 고른 값이 남는다
        let speedBefore = model.matchSpeed
        model.matchSpeed = 4
        check("배속: 저장", UserDefaults.standard.integer(forKey: "matchSpeed") == 4)
        model.matchSpeed = speedBefore

        // 9. 새 버전 확인: GitHub 응답 읽기 (네트워크는 쓰지 않는다)
        let notifiedBefore = UpdateChecker.notifiedHead
        defer { UpdateChecker.notifiedHead = notifiedBefore }
        let ahead = Data(#"{"ahead_by":3,"commits":[{"sha":"a1","commit":{"message":"첫 변경\n\n본문"}},{"sha":"b2","commit":{"message":"Merge pull request #1"}},{"sha":"c3","commit":{"message":"마지막 변경"}}]}"#.utf8)
        check("업데이트: 새 버전", UpdateChecker.parse(ahead)
            == .available(.init(count: 3, titles: ["마지막 변경", "첫 변경"], head: "c3")))
        check("업데이트: 최신", UpdateChecker.parse(Data(#"{"ahead_by":0,"commits":[]}"#.utf8)) == .upToDate)
        if case .unknown = UpdateChecker.parse(Data("{}".utf8)) { check("업데이트: 깨진 응답", true) } else { check("업데이트: 깨진 응답", false) }
        let release = Data(#"{"tag_name":"v0.10.0","name":"Token Sports 0.10.0","body":"변경 내용\n* 배속 추가\n* 버그 수정","html_url":"https://example.com/r","assets":[{"name":"a.txt","browser_download_url":"https://example.com/a.txt"},{"name":"a.dmg","browser_download_url":"https://example.com/a.dmg"}]}"#.utf8)
        if case .available(let found) = UpdateChecker.parseRelease(release, current: "0.9.3") {
            check("업데이트: 배포 버전", found.version == "0.10.0" && found.titles == ["배속 추가", "버그 수정"])
            check("업데이트: 내려받는 주소", found.download?.absoluteString == "https://example.com/a.dmg" && found.notes.count == 2)
        } else {
            check("업데이트: 배포 버전", false)
        }
        check("업데이트: 같은 배포 버전이면 최신", UpdateChecker.parseRelease(release, current: "0.10.0") == .upToDate)
        check("업데이트: 버전 비교", UpdateChecker.isVersion("0.10.0", newerThan: "0.9.9")
            && !UpdateChecker.isVersion("0.2.0", newerThan: "0.2.0") && !UpdateChecker.isVersion("0.1.9", newerThan: "0.2"))
        check("업데이트: 자동 설명 줄 정리", UpdateChecker.cleanNote("배속 추가 by @someone in https://github.com/o/r/pull/3") == "배속 추가"
            && UpdateChecker.cleanNote("그냥 줄") == "그냥 줄")
        // 배포 파일로 설치한 앱에서만 앱 안 업데이트가 된다.
        check("업데이트: 앱 안 업데이트는 배포 앱에서만", UpdateChecker.isReleaseBuild || Updater.blockedReason() != nil)
        // 자리 바꾸기: 예전 이름으로 설치된 앱은 새 이름으로 바뀌고, 새 이름의 앱은 제자리에서 바뀐다.
        func swapCheck(installedAs name: String) -> Bool {
            let fm = FileManager.default
            let root = directory.appendingPathComponent("swap-\(UUID().uuidString)", isDirectory: true)
            let installed = root.appendingPathComponent("apps/\(name)", isDirectory: true)
            let fresh = root.appendingPathComponent("work/\(Updater.appName)", isDirectory: true)
            try? fm.createDirectory(at: installed, withIntermediateDirectories: true)
            try? fm.createDirectory(at: fresh, withIntermediateDirectories: true)
            try? "old".write(to: installed.appendingPathComponent("mark"), atomically: true, encoding: .utf8)
            try? "new".write(to: fresh.appendingPathComponent("mark"), atomically: true, encoding: .utf8)
            // 이미 끝난 프로세스 번호를 주면 기다리지 않고 바로 바꾼다.
            try? Updater.swapAfterExit(fresh: fresh, into: installed, reopen: false, waitingFor: 99_999_999)
            let target = root.appendingPathComponent("apps/\(Updater.appName)/mark")
            for _ in 0..<50 {
                if (try? String(contentsOf: target, encoding: .utf8)) == "new",
                   !fm.fileExists(atPath: fresh.path) { break }
                Thread.sleep(forTimeInterval: 0.1)
            }
            let names = (try? fm.contentsOfDirectory(atPath: root.appendingPathComponent("apps").path)) ?? []
            let ok = names == [Updater.appName] && (try? String(contentsOf: target, encoding: .utf8)) == "new"
            try? fm.removeItem(at: root)
            return ok
        }
        check("업데이트: 예전 이름의 앱은 새 이름으로 바뀐다", swapCheck(installedAs: Updater.legacyAppName))
        check("업데이트: 새 이름의 앱은 제자리에서 바뀐다", swapCheck(installedAs: Updater.appName))
        model.apply(UpdateChecker.parse(ahead))
        check("업데이트: 앱에 표시", model.update?.count == 3 && model.updateStatus != nil)
        model.apply(.upToDate)
        check("업데이트: 최신이면 지움", model.update == nil)

        // 10. 초기화: 지금 모드만, 그리고 전체
        let resetSlot = model.slot
        let resetFile = model.store.fileURL.lastPathComponent
        let others = SaveSlot.allCases.filter { $0 != resetSlot && model.hasSave(slot: $0) }
        let backup = model.reset(all: false, now: Date(timeIntervalSince1970: 1_000))
        check("초기화: 지금 모드가 비었다", model.game == nil && !exists(resetFile) && model.slot == resetSlot, model.message ?? "")
        check("초기화: 다른 모드는 그대로", !others.isEmpty && others.allSatisfy { model.hasSave(slot: $0) })
        check("초기화: 백업에 남는다", backup.map { FileManager.default.fileExists(atPath: $0.appendingPathComponent(resetFile).path) } ?? false)
        check("초기화: 다시 켜도 비어 있다", AppModel(store: model.baseStore).game == nil)
        model.reset(all: true, now: Date(timeIntervalSince1970: 2_000))
        check("전체 초기화: 모두 비었다", SaveSlot.allCases.allSatisfy { !model.hasSave(slot: $0) } && model.game == nil, model.message ?? "")

        print(failures == 0 ? "SELFTEST 통과" : "SELFTEST 실패 \(failures)건")
        return failures == 0
    }
}
