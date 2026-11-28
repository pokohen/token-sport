import SwiftUI
import TokenBaseballCore

/// 명예의 전당: 이 세계에서 은퇴한 내 선수들. 누르면 그 선수의 커리어 기록이 펼쳐진다.
struct CareerHallCard: View {
    let game: Game
    /// 방금 은퇴한 선수는 위에 따로 보여 줄 때 여기서는 뺀다.
    var skipLatest = false
    @State private var open: Int?

    private var records: [(index: Int, record: CareerRecord)] {
        var all = Array((game.careerHall ?? []).enumerated()).map { (index: $0.offset, record: $0.element) }
        if skipLatest, !all.isEmpty { all.removeLast() }
        return all.reversed()
    }

    var body: some View {
        if !records.isEmpty {
            Card(String(localized: "명예의 전당"), trailing: String(localized: "\(records.count)명")) {
                ForEach(records, id: \.index) { item in
                    Button {
                        open = open == item.index ? nil : item.index
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(item.record.name) · \(item.record.position.localizedLabel)").font(.callout.weight(.medium))
                                Text("\(item.record.localizedHonor) · \(item.record.seasons)시즌 · 최고 \(item.record.bestTier.localizedDisplayName)").note()
                            }
                            Spacer()
                            Image(systemName: open == item.index ? "chevron.up" : "chevron.down").font(.caption)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    if open == item.index { CareerRecordCard(record: item.record) }
                }
                Text("은퇴한 선수의 기록이 여기에 남습니다. 이 모드를 초기화하면 함께 사라집니다 (backups 폴더에는 남습니다).").note()
            }
        }
    }
}
