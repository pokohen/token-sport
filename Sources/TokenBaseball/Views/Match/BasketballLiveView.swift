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
                LiveScoreLine(
                    awayName: state.away.name, awayScore: state.away.points,
                    homeName: state.home.name, homeScore: state.home.points)
                quarters
            }
            if let myName {
                MyPlayerLiveCard(name: myName, performance: myPerformance, waiting: "벤치에서 대기 중")
            }
            Card {
                let myBall = state.homeHasBall == live.userIsHome
                BasketballCourt(attackingRight: myBall, showsBall: !state.isFinished)
                    .accessibilityLabel(state.isFinished ? "코트" : "공 위치: \(myBall ? mine.shortName : theirs.shortName) 공격")
                if !state.isFinished {
                    AttackDirectionLabel(myBall: myBall, mine: mine.shortName, theirs: theirs.shortName)
                }
                let a = mine.totals, b = theirs.totals
                MirrorStatGrid(rows: [
                    .init("야투", shots(a.fieldGoalsMade, a.fieldGoalsAttempted), shots(b.fieldGoalsMade, b.fieldGoalsAttempted)),
                    .init("3점슛", shots(a.threesMade, a.threesAttempted), shots(b.threesMade, b.threesAttempted)),
                    .init("자유투", shots(a.freeThrowsMade, a.freeThrowsAttempted), shots(b.freeThrowsMade, b.freeThrowsAttempted)),
                    .init("리바운드", "\(a.rebounds)", "\(b.rebounds)"),
                    .init("어시스트", "\(a.assists)", "\(b.assists)"),
                    .init("스틸 · 블록", "\(a.steals) · \(a.blocks)", "\(b.steals) · \(b.blocks)"),
                    .init("실책", "\(a.turnovers)", "\(b.turnovers)"),
                ])
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
}

/// 농구 코트: 왼쪽 골대가 우리 골대, 오른쪽이 상대 골대. 공격하는 쪽 반코트를 밝히고 공을 그 앞에 둔다.
struct BasketballCourt: View {
    /// 공을 가진 팀이 오른쪽 골대로 공격하는지 (내 팀이 공격 중이면 true).
    let attackingRight: Bool
    var showsBall = true

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let line = GraphicsContext.Shading.color(.secondary.opacity(0.7))
            let floor = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6)
            context.fill(floor, with: .color(Theme.win.opacity(0.12)))
            // 공격하는 반코트를 밝힌다.
            if showsBall {
                let half = CGRect(x: attackingRight ? w / 2 : 0, y: 0, width: w / 2, height: h)
                context.fill(Path(half), with: .color(Theme.win.opacity(0.18)))
            }
            context.stroke(floor, with: line, lineWidth: 1)
            // 하프라인과 센터 서클
            var middle = Path()
            middle.move(to: CGPoint(x: w / 2, y: 0))
            middle.addLine(to: CGPoint(x: w / 2, y: h))
            context.stroke(middle, with: line, lineWidth: 1)
            let circle = h * 0.17
            context.stroke(Path(ellipseIn: CGRect(x: w / 2 - circle, y: h / 2 - circle, width: circle * 2, height: circle * 2)),
                           with: line, lineWidth: 1)
            // 양쪽 골밑: 페인트 존, 3점 라인, 림
            for right in [false, true] {
                let edge: CGFloat = right ? w : 0
                let toward: CGFloat = right ? -1 : 1
                let hoop = CGPoint(x: edge + toward * h * 0.14, y: h / 2)
                let paintWidth = h * 0.5, paintHeight = h * 0.32
                let paint = CGRect(x: right ? w - paintWidth : 0, y: h / 2 - paintHeight / 2, width: paintWidth, height: paintHeight)
                context.stroke(Path(paint), with: line, lineWidth: 1)
                var arc = Path()
                arc.addArc(center: hoop, radius: h * 0.44,
                           startAngle: .degrees(right ? 110 : -70), endAngle: .degrees(right ? 250 : 70), clockwise: false)
                context.stroke(arc, with: line, lineWidth: 1)
                let rim = h * 0.045
                context.stroke(Path(ellipseIn: CGRect(x: hoop.x - rim, y: hoop.y - rim, width: rim * 2, height: rim * 2)),
                               with: .color(.orange), lineWidth: 1.5)
            }
            // 공: 공격하는 골대 앞, 3점 라인 근처.
            if showsBall {
                let x = attackingRight ? w - h * 0.62 : h * 0.62
                let ball = context.resolve(Image(systemName: "basketball.fill"))
                context.draw(ball, at: CGPoint(x: x, y: h / 2), anchor: .center)
            }
        }
        .foregroundStyle(.orange)
        .frame(height: 64)
        .accessibilityElement(children: .ignore)
    }
}
