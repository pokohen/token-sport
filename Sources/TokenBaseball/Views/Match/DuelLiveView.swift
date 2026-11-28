import SwiftUI
import TokenBaseballCore

/// e스포츠 1:1 대전 팀 경기 중계. 배속은 경기 탭의 배속 카드에서 고른다.
/// 경기장 자리에 지금 세트의 미니맵을 그린다 (→ docs/10-esports.md "화면").
struct DuelLiveView: View {
    let live: LiveDuelMatch
    /// 선수 모드: 내 선수와 이 경기에서 지금까지의 평점.
    var me: Player? = nil
    var myPerformance: Game.CareerPerformance? = nil

    private var state: DuelMatch { live.state }
    private var mine: DuelMatch.Side { live.userIsHome ? state.home : state.away }
    private var theirs: DuelMatch.Side { live.userIsHome ? state.away : state.home }

    var body: some View {
        VStack(spacing: 10) {
            Card(live.kind.label, trailing: trailing) {
                LiveScoreLine(
                    awayName: state.away.name, awayScore: state.away.sets,
                    homeName: state.home.name, homeScore: state.home.sets)
                Text("\(state.bestOf)전 \(state.needed)선승 · 세트 점수").note()
                ForEach(state.records, id: \.number) { record in
                    let winner = record.homeWon ? record.home : record.away
                    KeyValueRow(
                        key: String(localized: "\(record.number)세트\(record.decider ? String(localized: " (에이스 결정전)") : "") · \(record.map)"),
                        value: String(localized: "\(winner.name)(\(winner.race.label)) 승"),
                        valueColor: (record.homeWon == live.userIsHome) ? Theme.win : Theme.loss)
                }
            }
            if let me {
                MyPlayerLiveCard(name: me.name, performance: myPerformance, waiting: waiting(me))
            }
            if let set = state.current {
                currentSet(set)
            } else if !state.isFinished {
                Card {
                    Text(state.isDecider ? "에이스 결정전을 준비합니다." : "\(state.records.count + 1)세트를 준비합니다.")
                        .font(.callout)
                }
            }
            CommentaryCard(log: state.log, myName: me?.name)
            OtherMatchesCard(rows: live.others.map {
                ("\(NameGenerator.shortName($0.away.name)) \($0.away.sets) : \($0.home.sets) \(NameGenerator.shortName($0.home.name))",
                 $0.isFinished ? String(localized: "종료") : String(localized: "\($0.records.count + 1)세트"))
            })
        }
    }

    private var trailing: String {
        if state.isFinished { return String(localized: "경기 종료") }
        guard let set = state.current else { return String(localized: "세트 사이") }
        return String(localized: "\(state.records.count + 1)세트 \(set.clockLabel)")
    }

    /// 내 선수가 지금 세트에 나와 있지 않을 때의 한 줄.
    private func waiting(_ me: Player) -> String {
        if state.isFinished { return String(localized: "이번 경기에는 나오지 않았습니다.") }
        guard mine.lineup.contains(me.id) else { return String(localized: "이번 경기에는 나오지 않습니다. 벤치에서 응원합니다.") }
        if let playing = state.currentPlayers {
            let id = live.userIsHome ? playing.home : playing.away
            if id != me.id, let name = mine.players[id]?.name { return String(localized: "이번 세트는 \(name) 선수가 나갑니다.") }
        }
        if mine.lineup.first == me.id { return String(localized: "에이스 결정전까지 가면 다시 나갑니다.") }
        return String(localized: "세트를 기다리는 중입니다.")
    }

    @ViewBuilder private func currentSet(_ set: DuelSet) -> some View {
        // 엔진의 0번 선수는 팀 경기의 홈 쪽이다.
        let myIndex = live.userIsHome ? 0 : 1
        let a = set.sides[myIndex], b = set.sides[1 - myIndex]
        Card(String(localized: "\(state.records.count + 1)세트 · \(set.map.name)"), trailing: set.stakes == .regular ? nil : String(localized: "에이스 결정전")) {
            HStack {
                Text("\(a.player.name) (\(a.player.race.label))").font(.callout.weight(.semibold)).foregroundStyle(Color.accentColor)
                Spacer()
                Text("대").note()
                Spacer()
                Text("\(b.player.name) (\(b.player.race.label))").font(.callout.weight(.semibold)).foregroundStyle(Theme.warn)
            }
            DuelMinimap(set: set, myIndex: myIndex)
                .accessibilityLabel("미니맵: 확장 \(a.bases) 대 \(b.bases)")
            Text(set.map.note).note()
            MirrorStatGrid(rows: [
                .init(String(localized: "확장"), "\(a.bases)", "\(b.bases)"),
                .init(String(localized: "병력"), "\(Int(a.army.rounded()))", "\(Int(b.army.rounded()))"),
                .init(String(localized: "일꾼"), "\(Int(a.workers.rounded()))", "\(Int(b.workers.rounded()))"),
                .init(String(localized: "잡은 병력"), "\(Int(a.armyKilled.rounded()))", "\(Int(b.armyKilled.rounded()))"),
                .init(String(localized: "빌드"), set.tick > 1 ? a.build.label : "-", set.tick > 1 ? b.build.label : "-"),
            ])
        }
    }
}

/// 맵의 미니맵: 왼쪽 아래가 우리 본진, 오른쪽 위가 상대 본진. 확장 자리를 맵 크기만큼 그리고,
/// 가져간 자리는 색으로 칠한다. 최근에 싸움이 난 곳에 점을 찍는다.
struct DuelMinimap: View {
    let set: DuelSet
    /// 내 선수가 엔진의 몇 번 선수인지.
    let myIndex: Int

    var body: some View {
        Canvas { context, size in
            let w = size.width, h = size.height
            let ground = Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 6)
            context.fill(ground, with: .color(Color.secondary.opacity(0.12)))
            context.stroke(ground, with: .color(.secondary.opacity(0.6)), lineWidth: 1)
            // 좁은 맵은 본진이 가깝고, 넓은 맵은 멀다.
            let inset: CGFloat = switch set.map.shape {
            case .narrow: 0.26
            case .wide: 0.1
            case .open: 0.16
            }
            let home = CGPoint(x: w * inset, y: h * (1 - inset))
            let away = CGPoint(x: w * (1 - inset), y: h * inset)
            // 길
            var road = Path()
            road.move(to: home)
            road.addLine(to: away)
            context.stroke(road, with: .color(.secondary.opacity(0.35)), style: StrokeStyle(lineWidth: 6, lineCap: .round))

            // 내 선수는 언제나 왼쪽 아래 (파랑), 상대는 오른쪽 위 (주황).
            let colors: [Color] = myIndex == 0 ? [.accentColor, Theme.warn] : [Theme.warn, .accentColor]
            for side in 0..<2 {
                let mineSide = side == myIndex
                let main = mineSide ? home : away
                let toward: CGFloat = mineSide ? 1 : -1
                let owned = set.sides[side].bases
                // 확장 자리: 본진에서 맵 가장자리를 따라 늘어선다.
                for slot in 0..<(set.map.maxBases - 1) {
                    let step = CGFloat(slot + 1)
                    let spot = slot % 2 == 0
                        ? CGPoint(x: main.x + toward * w * 0.11 * step, y: main.y)
                        : CGPoint(x: main.x, y: main.y - toward * h * 0.16 * step)
                    let rect = CGRect(x: spot.x - 5, y: spot.y - 5, width: 10, height: 10)
                    if slot + 2 <= owned {
                        context.fill(Path(ellipseIn: rect), with: .color(colors[side]))
                    } else {
                        context.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.6)), lineWidth: 1)
                    }
                }
                let base = CGRect(x: main.x - 9, y: main.y - 9, width: 18, height: 18)
                context.fill(Path(roundedRect: base, cornerRadius: 3), with: .color(colors[side]))
                // 병력 크기를 본진 옆 막대로.
                let army = min(1, set.sides[side].army / 120)
                let bar = CGRect(x: main.x - 9, y: main.y + (mineSide ? 12 : -16), width: 18 * army, height: 4)
                context.fill(Path(bar), with: .color(colors[side].opacity(0.7)))
            }
            // 최근 싸움
            if let spot = set.fightSpot, let tick = set.fightTick, set.tick - tick <= 3, !set.isFinished {
                let point: CGPoint = switch spot {
                case .center: CGPoint(x: w / 2, y: h / 2)
                case .base(let side): side == myIndex ? CGPoint(x: home.x + w * 0.06, y: home.y - h * 0.08)
                    : CGPoint(x: away.x - w * 0.06, y: away.y + h * 0.08)
                }
                let fight = CGRect(x: point.x - 7, y: point.y - 7, width: 14, height: 14)
                context.fill(Path(ellipseIn: fight), with: .color(Theme.loss.opacity(0.85)))
                context.stroke(Path(ellipseIn: fight.insetBy(dx: -3, dy: -3)), with: .color(Theme.loss.opacity(0.5)), lineWidth: 1.5)
            }
        }
        .frame(height: 120)
    }
}
