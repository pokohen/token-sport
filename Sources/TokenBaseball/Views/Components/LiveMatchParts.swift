import SwiftUI
import TokenBaseballCore

/// 종목과 상관없이 중계 화면에 공통으로 들어가는 조각들.

/// 문자 중계: 최근 여덟 줄. 내 선수가 나온 장면은 눈에 띄게 한다.
struct CommentaryCard: View {
    let log: [MatchEvent]
    var myName: String? = nil

    var body: some View {
        Card(String(localized: "문자 중계")) {
            ForEach(Array(log.suffix(8).reversed().enumerated()), id: \.offset) { index, event in
                let mine = myName.map { event.text.contains($0) } ?? false
                Text(event.text)
                    .font(index == 0 || mine ? .callout.weight(.semibold) : .callout)
                    .foregroundStyle(event.kind == .score ? Theme.win : mine ? Color.accentColor : index == 0 ? .primary : .secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if log.isEmpty { Text("곧 경기가 시작됩니다.").note() }
        }
    }
}

/// 선수 모드: 이 경기에서 지금까지의 내 선수 평점. 아직 나오지 않았으면 `waiting`을 보여 준다.
struct MyPlayerLiveCard: View {
    let name: String
    let performance: Game.CareerPerformance?
    let waiting: String

    var body: some View {
        Card {
            if let performance {
                KeyValueRow(
                    key: String(localized: "내 선수 \(name)"),
                    value: String(localized: "평점 \(String(format: "%.1f", performance.rating)) · \(performance.line)"),
                    valueColor: .accentColor)
            } else {
                KeyValueRow(key: String(localized: "내 선수 \(name)"), value: waiting)
            }
        }
    }
}

/// 같은 라운드의 다른 구장 소식.
struct OtherMatchesCard: View {
    /// (점수 한 줄, 진행 상황)
    let rows: [(score: String, status: String)]

    var body: some View {
        if !rows.isEmpty {
            Card(String(localized: "타 구장 소식")) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    KeyValueRow(key: row.score, value: row.status)
                }
            }
        }
    }
}

/// 끝난 내 경기의 결과와 정산.
struct LastResultCard: View {
    let result: LastResult

    var body: some View {
        Card(String(localized: "지난 경기"), trailing: result.kind.localizedLabel) {
            HStack {
                Text(result.localizedLabel).font(.title3.bold()).foregroundStyle(color)
                Text(result.wasHome ? "홈 vs \(result.opponent)" : "원정 vs \(result.opponent)").font(.callout)
            }
            ForEach(result.summary, id: \.self) { Text($0).note() }
        }
    }

    private var color: Color {
        if let won = result.shootoutWon { return won ? Theme.win : Theme.loss }
        return result.myRuns > result.theirRuns ? Theme.win : result.myRuns < result.theirRuns ? Theme.loss : .primary
    }
}

/// 중계 맨 위의 점수 줄: 원정 이름 · 점수 · 홈 이름.
struct LiveScoreLine: View {
    let awayName: String
    let awayScore: Int
    let homeName: String
    let homeScore: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(awayName).font(.callout.weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .trailing)
            Text("\(awayScore) : \(homeScore)").font(.title.bold().monospacedDigit())
            Text(homeName).font(.callout.weight(.semibold)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// 지금 공격하는 쪽. 내 공격이면 오른쪽(→), 상대 공격이면 왼쪽(←)에 붙는다.
struct AttackDirectionLabel: View {
    let myBall: Bool
    let mine: String
    let theirs: String

    var body: some View {
        Text(myBall ? "\(mine) 공격 →" : "← \(theirs) 공격")
            .font(.caption.weight(.medium))
            .foregroundStyle(myBall ? Theme.win : Theme.loss)
            .frame(maxWidth: .infinity, alignment: myBall ? .trailing : .leading)
    }
}

/// 두 팀 기록을 가운데 항목 이름을 두고 좌우로 견주는 표. 왼쪽이 내 팀이다.
struct MirrorStatGrid: View {
    struct Row {
        let label: String
        let mine: String
        let theirs: String
        init(_ label: String, _ mine: String, _ theirs: String) {
            self.label = label
            self.mine = mine
            self.theirs = theirs
        }
    }

    let rows: [Row]

    var body: some View {
        Grid(horizontalSpacing: 8, verticalSpacing: 3) {
            ForEach(rows.indices, id: \.self) { index in
                let row = rows[index]
                GridRow {
                    Text(row.mine).frame(maxWidth: .infinity, alignment: .trailing)
                    Text(row.label).foregroundStyle(.secondary).frame(width: 84)
                    Text(row.theirs).frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
        .font(.caption.monospacedDigit())
    }
}
