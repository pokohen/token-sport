import AppKit
import SwiftUI
import TokenBaseballCore

/// 도트로 그린 야구공, 축구공, 농구공.
///
/// 격자의 글자: `#` 테두리, `w` 흰 면, `r` 빨간 실밥(야구공), `k` 검은 조각(축구공),
/// `o` 주황 면과 `l` 검은 줄(농구공), `.` 빈칸.
enum BallSprite {
    static let baseball = [
        "....####....",
        "..##wwww##..",
        ".#wrwwwwrw#.",
        ".#wwrwwrww#.",
        "#wwwrwwrwww#",
        "#wwwrwwrwww#",
        "#wwwrwwrwww#",
        "#wwwrwwrwww#",
        ".#wwrwwrww#.",
        ".#wrwwwwrw#.",
        "..##wwww##..",
        "....####....",
    ]

    static let football = [
        "....####....",
        "..##kwwk##..",
        ".#kwwwwwwk#.",
        ".#wwwkkwww#.",
        "#wwwkkkkwww#",
        "#kwwkkkkwwk#",
        "#kwwwkkwwwk#",
        "#wwwwwwwwww#",
        ".#wkwwwwkw#.",
        ".#kkwwwwkk#.",
        "..##wkkw##..",
        "....####....",
    ]

    static let basketball = [
        "....####....",
        "..##olo###..",
        ".#oolooolo#.",
        ".#ooloooolo.",
        "#loolooooll#",
        "#olllllllll#",
        "#llllllllol#",
        "#oooloooloo#",
        ".#oolooolo#.",
        ".#olooolo##.",
        "..##oloo##..",
        "....####....",
    ]

    static func grid(_ sport: Sport) -> [String] {
        switch sport {
        case .baseball: baseball
        case .football: football
        case .basketball: basketball
        }
    }

    @MainActor private static var cache: [String: NSImage] = [:]

    /// 색이 있는 공 (앱 화면용). `size`는 한 변의 길이(pt).
    @MainActor
    static func image(_ sport: Sport, size: CGFloat) -> NSImage {
        draw(sport, size: size, template: false)
    }

    /// 한 가지 색으로만 그린 공 (상단바용). 상단바 색(밝은·어두운 모드)에 맞춰 칠해진다.
    @MainActor
    static func menuBarImage(_ sport: Sport) -> NSImage {
        draw(sport, size: 18, template: true)
    }

    @MainActor
    private static func draw(_ sport: Sport, size: CGFloat, template: Bool) -> NSImage {
        let key = "\(sport)-\(size)-\(template)"
        if let cached = cache[key] { return cached }
        let rows = grid(sport)
        let cell = size / CGFloat(rows.count)
        let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
            for (row, line) in rows.enumerated() {
                for (column, character) in line.enumerated() {
                    let color: NSColor?
                    switch character {
                    case "#": color = template ? .black : NSColor(white: 0.15, alpha: 1)
                    case "w": color = template ? nil : .white
                    case "r": color = template ? .black : NSColor(red: 0.85, green: 0.15, blue: 0.15, alpha: 1)
                    case "k": color = template ? .black : NSColor(white: 0.1, alpha: 1)
                    case "o": color = template ? nil : NSColor(red: 0.93, green: 0.49, blue: 0.13, alpha: 1)
                    case "l": color = template ? .black : NSColor(white: 0.12, alpha: 1)
                    default: color = nil
                    }
                    guard let color else { continue }
                    color.setFill()
                    // 칸 사이에 틈이 보이지 않게 살짝 겹쳐 칠한다.
                    NSRect(x: CGFloat(column) * cell, y: CGFloat(row) * cell, width: cell + 0.3, height: cell + 0.3).fill()
                }
            }
            return true
        }
        image.isTemplate = template
        cache[key] = image
        return image
    }
}

/// 화면에 넣는 도트 공.
struct BallIcon: View {
    let sport: Sport
    var size: CGFloat = 14

    var body: some View {
        Image(nsImage: BallSprite.image(sport, size: size))
            .interpolation(.none)
            .accessibilityLabel(sport == .football ? "축구공" : sport == .basketball ? "농구공" : "야구공")
    }
}
