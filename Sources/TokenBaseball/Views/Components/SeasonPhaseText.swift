import TokenBaseballCore

extension Game {
    /// 지금 시즌의 어디쯤인지 한 줄로 (예: "정규시즌 12/36").
    var phaseText: String {
        switch phase {
        case .regular: String(localized: "정규시즌 \(round)/\(roundsPerSeason)")
        case .playoff: String(localized: "승강 플레이오프")
        case .offseason: String(localized: "오프시즌 (친선 \(friendliesPlayed)/\(Balance.friendliesPerOffseason))")
        }
    }
}
