import SwiftUI
import TokenBaseballCore

struct CareerRecordCard: View {
    let record: CareerRecord

    var body: some View {
        Card("\(record.name) · \(record.position.label)", trailing: "\(record.honor) · \(record.seasons)시즌") {
            KeyValueRow(key: "은퇴 나이", value: "\(record.retiredAge)세")
            KeyValueRow(key: "거쳐 간 구단", value: "\(record.clubs.count)곳")
            Text(record.clubs.joined(separator: " → ")).note()
            KeyValueRow(key: "가장 높이 오른 리그", value: record.bestTier.displayName)
            KeyValueRow(key: "최고 능력", value: "\(Int(record.peakAbility))")
            if let basketball = record.basketball {
                KeyValueRow(key: "통산", value: CareerText.basketball(basketball))
            } else if let football = record.football {
                KeyValueRow(key: "통산", value: CareerText.football(football, keeper: record.position == .goalkeeper))
            } else if record.position.isPitcher {
                KeyValueRow(key: "통산", value: CareerText.pitching(record.pitching))
            } else {
                KeyValueRow(key: "통산", value: CareerText.batting(record.batting))
            }
            if let rating = record.averageRating {
                KeyValueRow(key: "평균 평점", value: String(format: "%.2f", rating))
            }
            KeyValueRow(key: "통산 수입", value: Format.money(record.earnings))
            if !record.awards.isEmpty { Text(record.awards.joined(separator: " · ")).note() }
        }
    }
}
