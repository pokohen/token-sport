import SwiftUI
import TokenBaseballCore

/// 실시간 중계 화면. 배속은 경기 탭의 배속 카드에서 고른다.
struct LiveMatchView: View {
    let live: LiveMatch
    /// 선수 모드: 내 선수 이름과 이 경기에서 지금까지의 평점.
    var myName: String? = nil
    var myPerformance: Game.CareerPerformance? = nil
    /// 선수 모드: 내 선수 (아직 나오지 않았을 때의 안내를 자리에 맞게 쓰려고).
    var myPlayer: Player? = nil

    private var state: MatchState { live.state }

    /// 내 선수가 아직 나오지 않았을 때의 안내.
    private var waiting: String {
        guard let me = myPlayer else { return String(localized: "아직 나오지 않았습니다") }
        let mine = live.userIsHome ? state.home : state.away
        switch me.position {
        case .starter:
            return mine.pitchers.first?.playerID == me.id ? String(localized: "곧 마운드에 오릅니다") : String(localized: "오늘은 등판하지 않는 날입니다")
        case .reliever, .closer:
            return String(localized: "불펜에서 대기 중")
        default:
            return String(localized: "아직 타석에 서지 않았습니다")
        }
    }

    var body: some View {
        VStack(spacing: 10) {
            Card(live.kind.localizedLabel, trailing: state.localizedInningLabel) {
                scoreboard
            }
            if let myName {
                MyPlayerLiveCard(name: myName, performance: myPerformance, waiting: waiting)
            }
            Card {
                HStack(alignment: .center, spacing: 16) {
                    diamond.frame(width: 110, height: 100)
                    VStack(alignment: .leading, spacing: 6) {
                        dots("B", filled: state.balls, of: 3, color: Theme.win)
                        dots("S", filled: state.strikes, of: 2, color: Theme.warn)
                        dots("O", filled: state.outs, of: 2, color: Theme.loss)
                    }
                    Spacer()
                }
            }
            Card {
                let pitcher = state.currentPitcher
                let batter = state.currentBatter
                KeyValueRow(key: String(localized: "투수 \(pitcher.name)"), value: String(localized: "\(pitcher.line.pitches)구"))
                KeyValueRow(key: String(localized: "타자 \(batter.name)"), value: String(localized: "\(batter.line.atBats)타수 \(batter.line.hits)안타"))
            }
            CommentaryCard(log: state.log, myName: myName)
            OtherMatchesCard(rows: live.others.map { ("\($0.away.shortName) \($0.away.runs) : \($0.home.runs) \($0.home.shortName)", $0.isFinished ? String(localized: "종료") : $0.localizedInningLabel) })
        }
    }

    private var scoreboard: some View {
        let innings = max(9, state.inning)
        return Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Text("").gridColumnAlignment(.leading)
                ForEach(1...innings, id: \.self) { Text("\($0)").foregroundStyle(.secondary) }
                Text("R").bold()
                Text("H").foregroundStyle(.secondary)
                Text("E").foregroundStyle(.secondary)
            }
            row(state.away, opponentErrors: state.away.errors, innings: innings)
            row(state.home, opponentErrors: state.home.errors, innings: innings)
        }
        .font(.caption.monospacedDigit())
    }

    private func row(_ team: MatchTeam, opponentErrors: Int, innings: Int) -> some View {
        GridRow {
            Text(team.shortName).font(.caption.weight(.semibold)).lineLimit(1)
            ForEach(0..<innings, id: \.self) { index in
                Text(index < team.runsByInning.count ? "\(team.runsByInning[index])" : " ")
            }
            Text("\(team.runs)").bold()
            Text("\(team.hits)")
            Text("\(opponentErrors)")
        }
    }

    private var diamond: some View {
        ZStack {
            base(filled: state.bases[1] != nil, label: String(localized: "2루")).offset(y: -34)
            base(filled: state.bases[2] != nil, label: String(localized: "3루")).offset(x: -38)
            base(filled: state.bases[0] != nil, label: String(localized: "1루")).offset(x: 38)
            Image(systemName: "house.fill").font(.caption).foregroundStyle(.secondary).offset(y: 34)
        }
    }

    private func base(filled: Bool, label: String) -> some View {
        Rectangle()
            .fill(filled ? Theme.warn : Color.secondary.opacity(0.25))
            .frame(width: 18, height: 18)
            .rotationEffect(.degrees(45))
            .accessibilityLabel(filled ? "\(label) 주자 있음" : "\(label) 비어 있음")
    }

    private func dots(_ label: String, filled: Int, of total: Int, color: Color) -> some View {
        HStack(spacing: 5) {
            Text(label).font(.caption.bold()).frame(width: 12)
            ForEach(0..<total, id: \.self) { index in
                Circle().fill(index < filled ? color : Color.secondary.opacity(0.25)).frame(width: 11, height: 11)
            }
        }
    }
}
