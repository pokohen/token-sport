import SwiftUI
import TokenBaseballCore

/// 커리어 탭: 나를 지켜보는 구단들과 관심도. 관심도가 기준을 넘으면 이적 기간에 제안이 온다.
struct CareerScoutCard: View {
    let game: Game
    let career: Career

    var body: some View {
        let scouts = game.careerScouts
        let threshold = game.careerScoutOfferThreshold
        Card("스카우트", trailing: scouts.isEmpty ? nil : "지켜보는 구단 \(scouts.count)/\(Balance.careerScoutMax)") {
            if career.isFreeAgent {
                Text("무소속일 때는 스카우트가 오지 않습니다. 입단 제안 가운데 하나를 고르세요.").note()
            } else if scouts.isEmpty {
                Text("아직 지켜보는 구단이 없습니다.").font(.callout)
            } else {
                ForEach(scouts) { scout in
                    row(scout, threshold: threshold)
                    if scout.id != scouts.last?.id { Divider() }
                }
            }
            if let visitor = game.careerScoutVisitor {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "binoculars.fill").accessibilityHidden(true)
                    Text("다음 경기에 \(visitor.name) 스카우트가 직접 보러 옵니다. 그 경기는 관심도가 두 배로 움직입니다.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout).foregroundStyle(Theme.warn)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Text(help(threshold)).note().fixedSize(horizontal: false, vertical: true)
        }
        .font(.callout)
    }

    private func row(_ scout: CareerScout, threshold: Double) -> some View {
        let team = game.teams[scout.teamID]
        let ready = scout.interest >= threshold
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                EmblemView(team: team, size: 24)
                VStack(alignment: .leading, spacing: 1) {
                    Text(team.name).font(.callout.weight(.medium)).lineLimit(1)
                    Text("\(team.tier.displayName) · \(game.rank(of: team.id))위 · 가면 \(game.careerRole(on: team.id).rawValue)").note()
                }
                Spacer()
                Text(change(scout.lastChange)).font(.caption.monospacedDigit())
                    .foregroundStyle(scout.lastChange > 0.5 ? Theme.win : scout.lastChange < -0.5 ? Theme.loss : .secondary)
            }
            Meter(label: "관심도", value: scout.interest, color: ready ? Theme.win : .accentColor)
            Text(status(scout, ready: ready, threshold: threshold)).note()
        }
        .accessibilityElement(children: .combine)
    }

    private func change(_ value: Double) -> String {
        let rounded = Int(value.rounded())
        return rounded > 0 ? "▲ \(rounded)" : rounded < 0 ? "▼ \(-rounded)" : "–"
    }

    private func status(_ scout: CareerScout, ready: Bool, threshold: Double) -> String {
        let watched = "지켜본 경기 \(scout.matchesWatched) · 직접 온 경기 \(scout.visits)"
        if ready {
            return game.tradeWindowOpen
                ? "\(watched) · 제안을 준비하고 있습니다"
                : "\(watched) · 이적 기간이 열리면 제안합니다"
        }
        return "\(watched) · 제안까지 \(Int((threshold - scout.interest).rounded(.up)))"
    }

    private func help(_ threshold: Double) -> String {
        var text = "경기를 뛸 때마다 평점에 따라 관심도가 오르내립니다. 그 구단에 가면 주전일수록, 명성이 높을수록 더 빨리 쌓입니다. 관심도가 \(Int(threshold))을 넘은 구단은 이적 기간에 제안을 보냅니다."
        if career.transferRequested {
            text += " 이적을 요청해 두어서 문턱이 낮아졌습니다."
        } else if (game.myPlayer?.contract.seasonsLeft ?? 1) <= 0 {
            text += " 계약이 끝나서 문턱이 낮아졌습니다."
        }
        text += " 제안을 거절하거나 답하지 않으면 그 구단은 떠납니다. 구단을 옮기면 처음부터 다시 쌓습니다."
        return text
    }
}
