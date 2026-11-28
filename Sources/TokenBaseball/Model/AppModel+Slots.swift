import AppKit
import Foundation
import SwiftUI
import TokenBaseballCore

/// 저장 칸(야구 구단 / 축구 구단 / 야구 선수 / 축구 선수)을 오가고, 새 구단·선수를 만든다.
extension AppModel {
    /// 그 종목의 구단을 이미 만들어 두었는지.
    func hasSave(for sport: Sport) -> Bool { baseStore.sibling(for: sport).exists }

    func hasSave(slot: SaveSlot) -> Bool { baseStore.sibling(slot: slot).exists }

    func switchSport(to target: Sport) { switchSlot(to: SaveSlot(sport: target)) }

    /// 저장 칸을 바꾼다. 지금 것은 저장해 두고, 그 칸의 구단·선수를 불러온다 (없으면 만들기 화면).
    /// 쉬는 구단·선수는 그동안 쓴 토큰과 흐른 시간을 받지 않는다.
    func switchSlot(to target: SaveSlot) {
        guard target != slot else { return }
        pendingSave?.cancel()
        save()
        // 칸을 적는 데 실패하면 여기서 돌아간다. 진행 중인 경기는 그대로 이어진다.
        do {
            try baseStore.saveActiveSlot(target)
        } catch {
            message = String(localized: "바꾸지 못했습니다: \(error.localizedDescription)")
            return
        }
        matchTask?.cancel()
        matchTask = nil
        matchGeneration += 1
        slot = target
        message = nil
        clearSlotCounters()
        loadGame()
        if game != nil {
            game?.resume(now: Date())
            save()
        }
        if game?.isMatchLive == true { runMatchLoop() }
        pollUsage()
    }

    /// 저장 칸마다 따로 세는 화면용 값(오늘 쓴 토큰, 최근 속도, 경기 가능 알림 기준)을 비운다.
    func clearSlotCounters() {
        wasMatchReady = nil
        todayTokens = 0
        recentRate = 0
    }

    func createClub(_ setup: Game.ClubSetup, sport chosen: Sport? = nil) {
        let name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { message = String(localized: "팀 이름을 입력해 주세요."); return }
        if game?.isBankrupt == true {
            perform { try $0.foundNewClub(setup: setup, now: Date()) }
        } else {
            let target = SaveSlot(sport: chosen ?? sport)
            // 이미 있는 구단을 덮어쓰지 않는다.
            guard !hasSave(slot: target) else {
                switchSlot(to: target)
                return
            }
            guard activate(target) else { return }
            let seed = UInt64.random(in: 1...UInt64.max)
            game = Game.newGame(setup: setup, now: Date(), seed: seed, sport: target.sport)
            message = nil
            save()
        }
        pollUsage()
    }

    /// 새로 만들 저장 칸으로 옮긴다. 실패하면 false.
    func activate(_ target: SaveSlot) -> Bool {
        guard target != slot else { return true }
        // 지금 진행하던 것은 저장해 두고 떠난다.
        pendingSave?.cancel()
        save()
        do {
            try baseStore.saveActiveSlot(target)
        } catch {
            message = String(localized: "만들지 못했습니다: \(error.localizedDescription)")
            return false
        }
        matchTask?.cancel()
        matchTask = nil
        matchGeneration += 1
        slot = target
        game = nil
        clearSlotCounters()
        return true
    }

    /// 선수 모드: 내 선수를 만든다. 은퇴한 뒤라면 같은 세계에서 새 선수로 시작한다.
    func createCareer(_ setup: CareerSetup) {
        var setup = setup
        setup.name = setup.name.trimmingCharacters(in: .whitespaces)
        guard !setup.name.isEmpty else { message = String(localized: "선수 이름을 입력해 주세요."); return }
        if slot.isCareer, game?.career?.retired == true {
            perform { try $0.startNewCareer(setup: setup, now: Date()) }
        } else {
            // 이미 있는 선수를 덮어쓰지 않는다.
            let target = SaveSlot.career(for: setup.sport)
            guard !hasSave(slot: target) else {
                switchSlot(to: target)
                return
            }
            guard activate(target) else { return }
            game = Game.newCareer(setup: setup, now: Date(), seed: UInt64.random(in: 1...UInt64.max))
            message = nil
            save()
        }
        pollUsage()
    }

    /// 초기화: 지금 모드만, 또는 모든 모드를 처음부터 다시 시작한다.
    /// 저장 파일은 지우지 않고 `backups/<날짜-시각>/`으로 옮겨 둔다. 옮긴 폴더를 돌려준다.
    @discardableResult
    func reset(all: Bool, now: Date = Date()) -> URL? {
        pendingSave?.cancel()
        matchTask?.cancel()
        matchTask = nil
        matchGeneration += 1
        // 초기화 직전 상태까지 백업에 담는다.
        save()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = formatter.string(from: now)
        var folder: URL?
        do {
            for target in all ? SaveSlot.allCases : [slot] {
                if let moved = try baseStore.sibling(slot: target).moveToBackup(named: name) {
                    folder = moved.deletingLastPathComponent()
                }
            }
        } catch {
            message = String(localized: "초기화하지 못했습니다: \(error.localizedDescription)")
            loadGame()
            if game?.isMatchLive == true { runMatchLoop() }
            return nil
        }
        game = nil
        loadError = nil
        message = nil
        clearSlotCounters()
        updateStatusTooltip()
        return folder
    }
}
