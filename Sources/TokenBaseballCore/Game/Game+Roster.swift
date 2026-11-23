import Foundation

extension Game {
    /// 이 선수를 내보내도 경기를 치를 인원이 남는지.
    func canSpare(_ id: PlayerID) -> Bool {
        let mates = roster(of: userTeamID).filter { $0.id != id }
        switch sport {
        case .football:
            return mates.count >= Balance.footballStarters && mates.contains { $0.position == .goalkeeper }
        case .baseball, .basketball:
            return mates.filter { !$0.isPitcher }.count >= Balance.minBatters
                && mates.filter { $0.isPitcher }.count >= Balance.minPitchers
        }
    }
}
