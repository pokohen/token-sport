import SwiftUI
import TokenBaseballCore

struct CareerHomeTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    var goToMatch: () -> Void = {}
    var goToCareer: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            if let career = game.career, let me = game.myPlayer {
                playerCard(career, me)
                notices(career)
                Card("훈련 포인트", trailing: "남은 훈련 \(max(0, career.sessionsLeft))/\(Balance.careerSessionsPerMatch)") {
                    Text("\(Format.tokens(game.funds.balance)) P").font(.title2.bold().monospacedDigit())
                    KeyValueRow(key: "오늘 번 포인트 (오늘 쓴 토큰)", value: "\(Format.tokens(model.todayTokens)) P")
                    KeyValueRow(key: "누적 포인트", value: "\(Format.tokens(game.funds.tokenIncome)) P")
                    Text("AI 코딩에 쓴 토큰이 그대로 훈련 포인트가 됩니다. 훈련 탭에서 능력치를 올리세요.").note()
                }
                if let goal = career.goal {
                    Card("시즌 목표") {
                        KeyValueRow(
                            key: goal.label,
                            value: goal.achieved.map { $0 ? "달성" : "실패" } ?? "\(goal.progress(of: me)) / \(goal.target)",
                            valueColor: goal.achieved == true ? Theme.win : goal.achieved == false ? Theme.loss : .primary)
                        Text("채우면 감독 신뢰 +10, 명성 +3. 채우지 못하면 감독 신뢰 −5.").note()
                    }
                }
                NextMatchCard(game: game, goToMatch: goToMatch)
                if let note = appearanceNote(me) { Text(note).note().frame(maxWidth: .infinity, alignment: .leading) }
                if let visitor = game.careerScoutVisitor, !game.isMatchLive {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "binoculars.fill").accessibilityHidden(true)
                        Text("\(visitor.tier.displayName) \(visitor.name) 스카우트가 다음 경기를 직접 보러 옵니다.")
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.callout.weight(.medium)).foregroundStyle(Theme.warn)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            NewsCard(game: game)
        }
    }

    private func playerCard(_ career: Career, _ me: Player) -> some View {
        Card {
            HStack(spacing: 12) {
                EmblemView(team: game.userTeam, size: 44)
                VStack(alignment: .leading, spacing: 2) {
                    Text(me.name).font(.headline)
                    Text(me.position.sport != .baseball
                        ? "\(me.age)세 · \(me.position.label)"
                        : "\(me.age)세 · \(me.position.label) · \(me.throwsHand.rawValue)투\(me.bats.rawValue)타").note()
                    Text(career.isFreeAgent
                        ? "무소속 · \(game.season)시즌"
                        : "\(game.userTeam.name) · \(game.userTier.displayName)").note()
                    Text("\(game.season)시즌 · \(game.phaseText)").note()
                }
                Spacer()
                VStack(alignment: .trailing) {
                    Text(me.grade).font(.title.bold())
                    Text("능력 \(String(format: "%.1f", me.ability))").note()
                }
            }
            if let talent = game.careerTalent {
                KeyValueRow(
                    key: "타고난 재능",
                    value: talent.rawValue + (career.startAbility.map { " · 타고난 능력 \(Int($0))" } ?? ""))
            }
            Meter(label: "감독 신뢰", value: career.trust, color: career.trust < Balance.careerRenewalTrust ? Theme.loss : .accentColor)
            Meter(label: "명성", value: career.fame, color: Theme.warn)
            form(career)
            if let rating = career.lastRating, let line = career.lastLine {
                KeyValueRow(key: "지난 경기", value: "평점 \(String(format: "%.1f", rating)) · \(line)")
            }
        }
    }

    /// 다음 경기의 컨디션, 기세, 연속 기록.
    @ViewBuilder private func form(_ career: Career) -> some View {
        let condition = game.careerCondition
        KeyValueRow(
            key: "다음 경기 컨디션", value: condition.label + percent(condition.modifier),
            valueColor: condition.modifier > 0 ? Theme.win : condition.modifier < 0 ? Theme.loss : .primary)
        if let streak = game.careerStreakText {
            KeyValueRow(
                key: game.careerStreak > 0 ? "기세" : "슬럼프", value: streak + percent(game.careerMomentum),
                valueColor: game.careerStreak > 0 ? Theme.win : Theme.loss)
        }
        if (career.run ?? 0) >= 2 || (career.bestRun ?? 0) >= 3 {
            KeyValueRow(key: game.careerRunLabel, value: "\(career.run ?? 0)경기 (최고 \(career.bestRun ?? 0)경기)")
        }
    }

    private func percent(_ modifier: Double) -> String {
        modifier == 0 ? "" : " (능력 \(modifier > 0 ? "+" : "−")\(Int((abs(modifier) * 100).rounded()))%)"
    }

    @ViewBuilder private func notices(_ career: Career) -> some View {
        if career.isFreeAgent {
            notice("무소속입니다. 입단 제안 중 하나를 골라야 경기에 나설 수 있습니다.", Theme.loss)
        } else if !career.offers.isEmpty {
            notice("답할 계약 제안이 \(career.offers.count)건 있습니다.", Theme.warn)
        } else if career.trust < Balance.careerRenewalTrust, game.myPlayer?.contract.seasonsLeft ?? 9 <= 1 {
            notice("감독 신뢰가 낮습니다. 계약이 끝나면 재계약 제안을 받지 못할 수 있습니다.", Theme.warn)
        }
    }

    private func notice(_ text: String, _ color: Color) -> some View {
        Banner(text: text, color: color, icon: "envelope.fill", action: goToCareer)
    }

    private func appearanceNote(_ me: Player) -> String? {
        guard game.nextMatch() != nil, !game.isMatchLive else { return nil }
        if (me.suspendedMatches ?? 0) > 0 { return "출장 정지로 다음 리그 경기에 나서지 못합니다." }
        if let plan = game.careerFootballPlan {
            if plan.starts { return "다음 경기에 선발로 나섭니다." }
            if let minute = plan.subMinute { return "다음 경기는 벤치에서 시작합니다. \(minute)분쯤 교체로 들어갑니다." }
            return "다음 경기는 벤치입니다. 골키퍼는 교체로 나오지 않습니다."
        }
        if let plan = game.careerBasketballPlan {
            if plan.starts { return "다음 경기에 선발로 나섭니다." }
            return "다음 경기는 벤치에서 시작합니다. \(plan.minutes ?? 0)분쯤 뜁니다 (감독 신뢰가 오르면 늘어납니다)."
        }
        switch me.position {
        case .starter:
            return game.careerStartsNextMatch ? "다음 경기에 선발로 등판합니다." : "다음 경기는 등판하지 않는 날입니다. 팀 경기를 지켜봅니다."
        case .reliever, .closer:
            return "선발이 내려가면 가장 먼저 올라옵니다."
        default:
            return "다음 경기에 선발로 나섭니다."
        }
    }
}
