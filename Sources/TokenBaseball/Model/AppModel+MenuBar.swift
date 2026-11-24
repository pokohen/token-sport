import AppKit
import Foundation
import SwiftUI
import TokenBaseballCore

/// 상단바: 글자, 툴팁, 훈련 애니메이션.
extension AppModel {
    /// 상단바 아이콘의 툴팁. MenuBarExtra의 라벨에 붙인 `.help`는 상단바 버튼까지 전달되지 않아서
    /// 버튼에 직접 넣는다.
    func updateStatusTooltip() {
        let text = tooltip
        for window in NSApp.windows {
            guard let button = Self.statusButton(in: window.contentView), button.toolTip != text else { continue }
            button.toolTip = text
        }
    }

    static func statusButton(in view: NSView?) -> NSStatusBarButton? {
        guard let view else { return nil }
        if let button = view as? NSStatusBarButton { return button }
        for child in view.subviews {
            if let button = statusButton(in: child) { return button }
        }
        return nil
    }

    func scheduleAnimation() {
        // 토큰을 많이 쓰는 중이면 애니메이션이 빨라진다 (사용량 = 훈련 강도).
        let interval = recentRate > 2_000_000 ? 0.18 : recentRate > 200_000 ? 0.28 : 0.45
        Timer.scheduledTimer(withTimeInterval: interval, repeats: false) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                if self.game?.settings.animationEnabled == true { self.frame &+= 1 }
                self.scheduleAnimation()
            }
        }
    }

    var menuBarText: String {
        guard let game else { return "Token Sports" }
        return game.menuBarText(now: now, todayTokens: todayTokens)
    }

    var tooltip: String {
        game?.menuBarTooltip(now: now, todayTokens: todayTokens) ?? "Token Sports"
    }

    /// 지금 보여줄 훈련 모습. 경기 중에는 상단바에 훈련 대신 공이 나오므로 여기서 따로 다루지 않는다.
    var drill: Sprites.Drill {
        guard let game, !game.isBankrupt else { return .rest }
        // 토큰 사용이 일정 시간 없으면 쉰다.
        // (장부의 반영 시각은 토큰을 안 써도 계속 갱신되므로 기준으로 쓸 수 없다.)
        if now.timeIntervalSince(lastTokenAt ?? launchedAt) > 600 { return .rest }
        var drills = game.myPlayer?.trainingDrills ?? game.sport.clubDrills
        if game.myPlayer == nil, game.userTeam.trainingLevel >= 3 { drills.append(.weights) }
        return drills[(Int(now.timeIntervalSince1970) / 8) % drills.count]
    }
}
