import SwiftUI
import TokenBaseballCore

/// 다음 경기와 경기 시작 버튼, 남은 경기 기회.
struct NextMatchCard: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var goToMatch: () -> Void = {}

    var body: some View {
        Card("다음 경기", accessory: AnyView(ChargeMarks(sport: game.sport, charges: game.charges))) {
            if game.isMatchLive {
                Text("경기가 진행 중입니다.").font(.callout)
                Button("중계 보기", action: goToMatch)
            } else if let next = game.nextMatch() {
                let opponent = game.teams[next.opponent]
                // 몇 번째 경기인지 크게 적는다.
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(next.label).font(.title2.bold().monospacedDigit())
                    if next.kind == .regular {
                        Text("/ 전체 \(game.roundsPerSeason)라운드").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text("\(game.season)시즌").note()
                }
                .accessibilityElement(children: .combine)
                HStack {
                    EmblemView(team: opponent, size: 28)
                    VStack(alignment: .leading) {
                        Text("\(next.userIsHome ? "홈" : "원정") vs \(opponent.name)").font(.callout.weight(.medium))
                        Text("\(opponent.tier.displayName) · 강도 \(Int(game.strength(of: opponent.id)))\(game.sport == .football ? " · \(game.formation(of: opponent.id).label)" : "")").note()
                    }
                    Spacer()
                    Button("경기 시작") {
                        model.startMatch()
                        if model.game?.isMatchLive == true { goToMatch() }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(game.charges == 0)
                }
                if game.charges == 0 {
                    if let wait = game.timeToNextCharge(now: model.now) {
                        // 얼마나 남았는지, 몇 시에 되는지, 얼마나 찼는지를 함께 보여 준다.
                        HStack(spacing: 8) {
                            Text("다음 경기까지 \(Format.countdown(wait))").font(.callout.weight(.medium))
                            Text("\(model.now.addingTimeInterval(wait).formatted(date: .omitted, time: .shortened))에 가능").note()
                            Spacer()
                        }
                        Bar(fraction: 1 - wait / Balance.matchChargeInterval)
                    }
                    HStack {
                        Text("기다리지 않고 \(game.isCareer ? "훈련 포인트" : "자금")로 바로 치를 수 있습니다. 연달아 쓰면 두 배씩 비싸지고, 경기 기회가 새로 생기면 처음 값으로 돌아갑니다.\(game.isCareer ? " 이렇게 치른 경기에서는 실전 경험으로 능력이 조금 오릅니다 (평점이 좋을수록 많이)." : "")").note()
                        Spacer()
                        Button("바로 경기 · \(game.fundsText(game.extraMatchCost))") {
                            model.buyExtraMatchAndStart()
                            if model.game?.isMatchLive == true { goToMatch() }
                        }
                        .disabled(game.extraMatchBlockedReason != nil)
                        .help(game.extraMatchBlockedReason ?? "경기 기회를 하나 사서 바로 시작합니다")
                    }
                }
            } else {
                Text("지금은 치를 경기가 없습니다.").note()
            }
        }
    }
}

/// 남은 경기 기회: 있는 만큼 공으로, 빈 자리는 동그라미로.
struct ChargeMarks: View {
    let sport: Sport
    let charges: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<Balance.maxMatchCharges, id: \.self) { index in
                if index < charges {
                    BallIcon(sport: sport, size: 13)
                } else {
                    Circle().stroke(Color.secondary.opacity(0.6), lineWidth: 1).frame(width: 11, height: 11)
                }
            }
        }
        .accessibilityLabel("경기 기회 \(charges)개")
    }
}
