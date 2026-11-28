import SwiftUI
import TokenBaseballCore

enum Theme {
    static let popoverWidth: CGFloat = 420
    static let popoverHeight: CGFloat = 600

    static let teamColors: [Color] = [
        Color(red: 0.16, green: 0.42, blue: 0.80), Color(red: 0.78, green: 0.22, blue: 0.22),
        Color(red: 0.13, green: 0.55, blue: 0.38), Color(red: 0.85, green: 0.52, blue: 0.10),
        Color(red: 0.45, green: 0.30, blue: 0.72), Color(red: 0.10, green: 0.55, blue: 0.62),
        Color(red: 0.72, green: 0.28, blue: 0.52), Color(red: 0.35, green: 0.38, blue: 0.45),
    ]
    static let teamColorNames = [String(localized: "파랑"), String(localized: "빨강"), String(localized: "초록"), String(localized: "주황"), String(localized: "보라"), String(localized: "청록"), String(localized: "자주"), String(localized: "회색")]
    static let emblems = ["shield.fill", "star.fill", "flame.fill", "bolt.fill", "leaf.fill", "crown.fill"]
    static let emblemNames = [String(localized: "방패"), String(localized: "별"), String(localized: "불꽃"), String(localized: "번개"), String(localized: "잎"), String(localized: "왕관")]

    static func color(_ team: Team) -> Color { teamColors[team.colorIndex % teamColors.count] }
    static func emblem(_ team: Team) -> String { emblems[team.emblemIndex % emblems.count] }

    static let win = Color(red: 0.13, green: 0.55, blue: 0.38)
    static let loss = Color(red: 0.78, green: 0.22, blue: 0.22)
    static let warn = Color(red: 0.85, green: 0.52, blue: 0.10)
}
