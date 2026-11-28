import SwiftUI
import TokenBaseballCore

/// 축구 실시간 중계 화면. 배속은 경기 탭의 배속 카드에서 고른다.
struct FootballLiveView: View {
    let live: LiveFootballMatch
    /// 선수 모드: 내 선수 이름과 이 경기에서 지금까지의 평점.
    var myName: String? = nil
    var myPerformance: Game.CareerPerformance? = nil

    private var state: FootballMatch { live.state }
    private var mine: FootballSide { live.userIsHome ? state.home : state.away }
    private var theirs: FootballSide { live.userIsHome ? state.away : state.home }

    var body: some View {
        VStack(spacing: 10) {
            Card(live.kind.localizedLabel, trailing: "\(state.localizedPeriodLabel) \(state.localizedClockLabel)") {
                LiveScoreLine(
                    awayName: state.away.name, awayScore: state.away.goals,
                    homeName: state.home.name, homeScore: state.home.goals)
                HStack {
                    Text("원정 · \(state.away.shape.label)").frame(maxWidth: .infinity, alignment: .trailing)
                    Text(state.wentToShootout ? "승부차기 \(state.away.shootoutGoals) : \(state.home.shootoutGoals)" : " ")
                    Text("홈 · \(state.home.shape.label)").frame(maxWidth: .infinity, alignment: .leading)
                }
                .note()
            }
            if let myName {
                MyPlayerLiveCard(name: myName, performance: myPerformance, waiting: String(localized: "벤치에서 대기 중"))
            }
            Card {
                pitch
                let share = Int(((live.userIsHome ? state.homePossession : 1 - state.homePossession) * 100).rounded())
                MirrorStatGrid(rows: [
                    .init(String(localized: "점유율"), "\(share)%", "\(100 - share)%"),
                    .init(String(localized: "슈팅 (유효)"), "\(mine.shots) (\(mine.shotsOnTarget))", "\(theirs.shots) (\(theirs.shotsOnTarget))"),
                    .init(String(localized: "코너킥"), "\(mine.corners)", "\(theirs.corners)"),
                    .init(String(localized: "반칙"), "\(mine.fouls)", "\(theirs.fouls)"),
                    .init(String(localized: "경고 · 퇴장"), "\(mine.yellowCards) · \(mine.redCards)", "\(theirs.yellowCards) · \(theirs.redCards)"),
                ])
            }
            CommentaryCard(log: state.log, myName: myName)
            OtherMatchesCard(rows: live.others.map { ("\($0.away.shortName) \($0.away.goals) : \($0.home.goals) \($0.home.shortName)", $0.isFinished ? String(localized: "종료") : $0.localizedClockLabel) })
        }
    }

    /// 경기장: 왼쪽이 내 진영, 오른쪽이 상대 진영.
    private var pitch: some View {
        let fromMine = live.userIsHome ? state.ballZoneFromHome : 2 - state.ballZoneFromHome
        let myBall = state.homeHasBall == live.userIsHome
        let labels = [String(localized: "우리 진영"), String(localized: "중원"), String(localized: "상대 진영")]
        return VStack(spacing: 4) {
            HStack(spacing: 2) {
                ForEach(0..<3, id: \.self) { zone in
                    ZStack {
                        Rectangle().fill(Theme.win.opacity(zone == fromMine ? 0.30 : 0.12))
                        VStack(spacing: 2) {
                            Image(systemName: "soccerball").font(.callout)
                                .opacity(zone == fromMine && !state.isFinished ? 1 : 0)
                            Text(labels[zone]).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    .frame(height: 54)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("공 위치: \(labels[fromMine])")
            if state.period != .shootout, !state.isFinished {
                AttackDirectionLabel(myBall: myBall, mine: mine.shortName, theirs: theirs.shortName)
            }
        }
    }
}
