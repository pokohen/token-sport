import SwiftUI
import TokenBaseballCore

/// 커리어 탭: 라이벌과 나를 나란히 놓고 본다.
struct CareerRivalCard: View {
    let game: Game
    let career: Career
    let me: Player

    var body: some View {
        if let record = career.rival, let rival = game.careerRival, let team = rival.teamID {
            Card("라이벌", trailing: "맞대결 \(record.wins)승 \(record.draws)무 \(record.losses)패") {
                HStack(spacing: 10) {
                    EmblemView(team: game.teams[team], size: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(rival.name).font(.callout.weight(.semibold))
                        Text("\(game.teams[team].name) · \(rival.age)세 · \(rival.position.label)").note()
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 1) {
                        Text("능력 \(Int(rival.ability))").font(.callout.monospacedDigit())
                        Text("내 능력 \(Int(me.ability))").note()
                    }
                }
                Divider()
                KeyValueRow(key: "나", value: line(me))
                KeyValueRow(key: rival.name, value: line(rival))
                if let last = record.lastMeeting { Text(last).note().fixedSize(horizontal: false, vertical: true) }
                Text("같은 리그에서 나와 비슷한 선수입니다. 그 구단과 만나 둘 다 뛴 날, 평점이 높은 쪽이 맞대결에서 이깁니다. 이기면 명성이 \(Int(Balance.careerRivalFame)) 오릅니다. 리그가 달라지거나 새 시즌에 내가 크게 앞서 있으면 새 라이벌이 생깁니다.").note().fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func line(_ player: Player) -> String {
        CareerText.record(
            player, batting: player.batting, pitching: player.pitching, football: player.football,
            basketball: player.basketball)
    }
}
