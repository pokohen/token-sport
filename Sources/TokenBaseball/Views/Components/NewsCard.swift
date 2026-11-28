import SwiftUI
import TokenBaseballCore

/// 최근 소식 (새 것부터).
struct NewsCard: View {
    let game: Game
    var count = 12

    var body: some View {
        Card(String(localized: "소식")) {
            let recent = game.news.suffix(count)
            if recent.isEmpty { Text("아직 소식이 없습니다.").note() }
            ForEach(recent.reversed()) { item in
                Text(item.text).font(.callout).frame(maxWidth: .infinity, alignment: .leading)
                if item.id != recent.first?.id { Divider() }
            }
        }
    }
}
