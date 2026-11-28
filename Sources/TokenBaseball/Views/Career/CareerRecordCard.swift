import SwiftUI
import TokenBaseballCore

struct CareerRecordCard: View {
    let record: CareerRecord

    var body: some View {
        Card("\(record.name) · \(record.position.localizedLabel)", trailing: String(localized: "\(record.localizedHonor) · \(record.seasons)시즌")) {
            KeyValueRow(key: String(localized: "은퇴 나이"), value: String(localized: "\(record.retiredAge)세"))
            KeyValueRow(key: String(localized: "거쳐 간 구단"), value: String(localized: "\(record.clubs.count)곳"))
            Text(record.clubs.joined(separator: " → ")).note()
            KeyValueRow(key: String(localized: "가장 높이 오른 리그"), value: record.bestTier.localizedDisplayName)
            KeyValueRow(key: String(localized: "최고 능력"), value: "\(Int(record.peakAbility))")
            if let basketball = record.basketball {
                KeyValueRow(key: String(localized: "통산"), value: CareerText.basketball(basketball))
            } else if let football = record.football {
                KeyValueRow(key: String(localized: "통산"), value: CareerText.football(football, keeper: record.position == .goalkeeper))
            } else if record.position.isPitcher {
                KeyValueRow(key: String(localized: "통산"), value: CareerText.pitching(record.pitching))
            } else {
                KeyValueRow(key: String(localized: "통산"), value: CareerText.batting(record.batting))
            }
            if let rating = record.averageRating {
                KeyValueRow(key: String(localized: "평균 평점"), value: String(format: "%.2f", rating))
            }
            KeyValueRow(key: String(localized: "통산 수입"), value: DisplayFormat.money(record.earnings))
            if !record.awards.isEmpty { Text(record.awards.joined(separator: " · ")).note() }
        }
    }
}
