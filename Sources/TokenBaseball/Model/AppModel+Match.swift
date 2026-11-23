import AppKit
import Foundation
import SwiftUI
import TokenBaseballCore

/// 경기 시작과 실시간 중계 진행, 알림.
extension AppModel {
    func startMatch() {
        perform { try $0.startMatch(now: Date()) }
        save()
        if game?.isMatchLive == true { runMatchLoop() }
    }

    /// 토큰으로 경기 기회를 하나 사서 곧바로 경기를 시작한다.
    func buyExtraMatchAndStart() {
        perform { try $0.buyExtraMatch(now: Date()) }
        guard message == nil else { return }
        startMatch()
    }

    /// 토큰을 내고 진행 중인 경기를 곧바로 끝낸다. 돌던 중계는 여기서 멈춘다.
    func skipMatch() {
        perform { try $0.skipMatchToEnd() }
        guard message == nil else { return }
        matchTask?.cancel()
        matchTask = nil
        matchGeneration += 1
        matchDidFinish()
    }

    func acknowledgeResult() {
        guard game?.lastResult?.acknowledged == false else { return }
        game?.acknowledgeResult()
        save()
    }

    /// 팝오버가 열리고 닫힐 때 부른다.
    func setPopoverVisible(_ visible: Bool) {
        popoverVisible = visible
        if visible { acknowledgeResult() }
    }

    func runMatchLoop() {
        guard matchTask == nil else { return }
        let generation = matchGeneration
        matchTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, self.matchGeneration == generation, self.game?.isMatchLive == true else { break }
                let before = self.game?.liveScore?.mine
                let events = self.game?.stepMatch() ?? []
                let after = self.game?.liveScore?.mine
                self.handle(events, iScored: before != nil && after != nil && after! > before!)
                // 이닝 교대, 투수 교체, 득점 장면에서는 잠깐 멈췄다 간다.
                var pause = Self.pitchInterval
                if events.contains(where: { $0.kind == .inning }) { pause += .seconds(4) }
                if events.contains(where: { $0.kind == .change }) { pause += .seconds(3) }
                // 농구는 득점이 워낙 잦아서 득점마다 멈추지 않는다.
                if self.sport != .basketball, events.contains(where: { $0.kind == .score }) { pause += .seconds(2) }
                if self.game?.isMatchLive != true { break }
                // 배속: 기다리는 시간만 줄인다. 경기 내용은 배속과 상관없이 같다.
                try? await Task.sleep(for: pause / max(1, self.matchSpeed))
            }
            if let self, self.matchGeneration == generation { self.matchTask = nil }
        }
    }

    func handle(_ events: [MatchEvent], iScored: Bool) {
        pitchesSinceSave += 1
        if game?.isMatchLive != true { return matchDidFinish() }
        if iScored, sport != .basketball {
            notify(sport == .football ? "골!" : "득점!", events.last { $0.kind == .score }?.text ?? "")
        }
        if pitchesSinceSave >= 15 || events.contains(where: { $0.kind == .inning }) {
            pitchesSinceSave = 0
            save()
        }
    }

    /// 내 경기가 끝났다 (끝까지 봤든 결과 바로 보기를 했든): 알리고 곧바로 저장한다.
    func matchDidFinish() {
        if let result = game?.lastResult {
            notify("경기 종료", "\(result.opponent)전 \(result.label)")
            // 팝오버로 결과를 보고 있었으면 상단바에 "경기 종료"를 남기지 않는다.
            if popoverVisible { game?.acknowledgeResult() }
        }
        pitchesSinceSave = 0
        pendingSave?.cancel()
        save()
    }

    func notify(_ title: String, _ body: String) {
        guard game?.settings.notificationsEnabled == true else { return }
        Notifier.send(title: title, body: body)
    }
}
