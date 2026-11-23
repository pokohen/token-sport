import SwiftUI
import TokenBaseballCore

/// 농구 실시간 중계 화면. 배속은 경기 탭의 배속 카드에서 고른다.
struct BasketballLiveView: View {
    let live: LiveBasketballMatch
    /// 선수 모드: 내 선수 이름과 이 경기에서 지금까지의 평점.
    var myName: String? = nil
    var myPerformance: Game.CareerPerformance? = nil

    private var state: BasketballMatch { live.state }
    private var mine: BasketballSide { live.userIsHome ? state.home : state.away }
    private var theirs: BasketballSide { live.userIsHome ? state.away : state.home }

    var body: some View {
        VStack(spacing: 10) {
            Card(live.kind.label, trailing: state.isFinished ? "경기 종료" : state.clockLabel) {
                HStack(alignment: .firstTextBaseline) {
                    Text(state.away.name).font(.callout.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                    Text("\(state.away.points) : \(state.home.points)").font(.title.bold().monospacedDigit())
                    Text(state.home.name).font(.callout.weight(.semibold)).lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                quarters
            }
            if let myName {
                MyPlayerLiveCard(name: myName, performance: myPerformance, waiting: "벤치에서 대기 중")
            }
            Card {
                if !state.isFinished {
                    let myBall = state.homeHasBall == live.userIsHome
                    Text(myBall ? "\(mine.shortName) 공격 →" : "← \(theirs.shortName) 공격")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(myBall ? Theme.win : Theme.loss)
                        .frame(maxWidth: .infinity, alignment: myBall ? .trailing : .leading)
                }
                let a = mine.totals, b = theirs.totals
                Grid(horizontalSpacing: 8, verticalSpacing: 3) {
                    statRow("야투", shots(a.fieldGoalsMade, a.fieldGoalsAttempted), shots(b.fieldGoalsMade, b.fieldGoalsAttempted))
                    statRow("3점슛", shots(a.threesMade, a.threesAttempted), shots(b.threesMade, b.threesAttempted))
                    statRow("자유투", shots(a.freeThrowsMade, a.freeThrowsAttempted), shots(b.freeThrowsMade, b.freeThrowsAttempted))
                    statRow("리바운드", "\(a.rebounds)", "\(b.rebounds)")
                    statRow("어시스트", "\(a.assists)", "\(b.assists)")
                    statRow("스틸 · 블록", "\(a.steals) · \(a.blocks)", "\(b.steals) · \(b.blocks)")
                    statRow("실책", "\(a.turnovers)", "\(b.turnovers)")
                }
                .font(.caption.monospacedDigit())
            }
            CommentaryCard(log: state.log, myName: myName)
            OtherMatchesCard(rows: live.others.map {
                ("\($0.away.shortName) \($0.away.points) : \($0.home.points) \($0.home.shortName)", $0.isFinished ? "종료" : $0.clockLabel)
            })
        }
    }

    /// 쿼터별 점수.
    private var quarters: some View {
        let count = max(state.home.pointsByPeriod.count, BasketballMatch.quarters)
        return Grid(horizontalSpacing: 6, verticalSpacing: 2) {
            GridRow {
                Text("").frame(maxWidth: .infinity, alignment: .leading)
                ForEach(0..<count, id: \.self) { index in
                    Text(index < BasketballMatch.quarters ? "\(index + 1)Q" : "연장").frame(width: 30)
                }
            }
            .foregroundStyle(.secondary)
            row(state.away, count: count)
            row(state.home, count: count)
        }
        .font(.caption.monospacedDigit())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("쿼터별 점수")
    }

    private func row(_ side: BasketballSide, count: Int) -> some View {
        GridRow {
            Text(side.shortName).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
            ForEach(0..<count, id: \.self) { index in
                Text(index < side.pointsByPeriod.count ? "\(side.pointsByPeriod[index])" : "-").frame(width: 30)
            }
        }
    }

    private func shots(_ made: Int, _ tried: Int) -> String {
        tried == 0 ? "0/0" : "\(made)/\(tried) (\(Int((Double(made) / Double(tried) * 100).rounded()))%)"
    }

    private func statRow(_ label: String, _ left: String, _ right: String) -> some View {
        GridRow {
            Text(left).frame(maxWidth: .infinity, alignment: .trailing)
            Text(label).foregroundStyle(.secondary).frame(width: 84)
            Text(right).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}
