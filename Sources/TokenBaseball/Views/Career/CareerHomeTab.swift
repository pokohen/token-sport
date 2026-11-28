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
                Card(String(localized: "훈련 포인트"), trailing: String(localized: "남은 훈련 \(max(0, career.sessionsLeft))/\(Balance.careerSessionsPerMatch)")) {
                    Text("\(Format.tokens(game.funds.balance)) P").font(.title2.bold().monospacedDigit())
                    KeyValueRow(key: String(localized: "오늘 번 포인트 (오늘 쓴 토큰)"), value: "\(Format.tokens(model.todayTokens)) P")
                    KeyValueRow(key: String(localized: "누적 포인트"), value: "\(Format.tokens(game.funds.tokenIncome)) P")
                    Text("AI 코딩에 쓴 토큰이 그대로 훈련 포인트가 됩니다. 훈련 탭에서 능력치를 올리세요.").note()
                }
                if let goal = career.goal {
                    Card(String(localized: "시즌 목표")) {
                        KeyValueRow(
                            key: goal.localizedLabel,
                            value: goal.achieved.map { $0 ? String(localized: "달성") : String(localized: "실패") } ?? "\(goal.progress(of: me)) / \(goal.target)",
                            valueColor: goal.achieved == true ? Theme.win : goal.achieved == false ? Theme.loss : .primary)
                        if game.sport != .duel { Text("채우면 감독 신뢰 +10, 명성 +3. 채우지 못하면 감독 신뢰 −5.").note() }
                    }
                }
                NextMatchCard(game: game, goToMatch: goToMatch)
                if let note = appearanceNote(me) { Text(note).note().frame(maxWidth: .infinity, alignment: .leading) }
                if let visitor = game.careerScoutVisitor, !game.isMatchLive {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "binoculars.fill").accessibilityHidden(true)
                        Text("\(visitor.tier.localizedDisplayName(for: game.sport)) \(visitor.name) 스카우트가 다음 경기를 직접 보러 옵니다.")
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
                    Text([String(localized: "\(me.age)세"), me.position.localizedLabel, me.handedness].compactMap { $0 }.joined(separator: " · ")).note()
                    Text(career.isFreeAgent
                        ? "무소속 · \(game.season)시즌"
                        : "\(game.userTeam.name) · \(game.userTier.localizedDisplayName(for: game.sport))").note()
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
                    key: String(localized: "타고난 재능"),
                    value: talent.localizedName + (career.startAbility.map { String(localized: " · 타고난 능력 \(Int($0))") } ?? ""))
            }
            if let fans = career.fans {
                // e스포츠: 감독 신뢰 대신 팬 수. 명성은 팬 수에서 나온다.
                KeyValueRow(key: String(localized: "팬"), value: DisplayFormat.fans(fans))
                if let title = game.localizedDuelTitle { KeyValueRow(key: String(localized: "칭호"), value: title, valueColor: Theme.warn) }
                if let next = game.nextDuelTournament {
                    KeyValueRow(
                        key: String(localized: "다음 개인 대회 (\(next.round)라운드 뒤)"),
                        value: next.eligible ? next.tournament.localizedBaseName : String(localized: "\(next.tournament.localizedBaseName) · 팬 \(DisplayFormat.fans(next.tournament.requiredFans)) 필요"))
                }
            } else {
                Meter(label: String(localized: "감독 신뢰"), value: career.trust, color: career.trust < Balance.careerRenewalTrust ? Theme.loss : .accentColor)
                Meter(label: String(localized: "명성"), value: career.fame, color: Theme.warn)
            }
            form(career)
            if let rating = career.lastRating, let line = career.lastLine {
                KeyValueRow(key: String(localized: "지난 경기"), value: String(localized: "평점 \(String(format: "%.1f", rating)) · \(line)"))
            }
        }
    }

    /// 다음 경기의 컨디션, 기세, 연속 기록.
    @ViewBuilder private func form(_ career: Career) -> some View {
        let condition = game.careerCondition
        KeyValueRow(
            key: String(localized: "다음 경기 컨디션"), value: condition.localizedLabel + percent(condition.modifier),
            valueColor: condition.modifier > 0 ? Theme.win : condition.modifier < 0 ? Theme.loss : .primary)
        if let streak = game.localizedCareerStreakText {
            KeyValueRow(
                key: game.careerStreak > 0 ? String(localized: "기세") : String(localized: "슬럼프"), value: streak + percent(game.careerMomentum),
                valueColor: game.careerStreak > 0 ? Theme.win : Theme.loss)
        }
        if (career.run ?? 0) >= 2 || (career.bestRun ?? 0) >= 3 {
            KeyValueRow(key: game.localizedCareerRunLabel, value: String(localized: "\(career.run ?? 0)경기 (최고 \(career.bestRun ?? 0)경기)"))
        }
    }

    private func percent(_ modifier: Double) -> String {
        modifier == 0 ? "" : String(localized: " (능력 \(modifier > 0 ? "+" : "−")\(Int((abs(modifier) * 100).rounded()))%)")
    }

    @ViewBuilder private func notices(_ career: Career) -> some View {
        if career.isFreeAgent {
            notice(String(localized: "무소속입니다. 입단 제안 중 하나를 골라야 경기에 나설 수 있습니다."), Theme.loss)
        } else if !career.offers.isEmpty {
            notice(String(localized: "답할 계약 제안이 \(career.offers.count)건 있습니다."), Theme.warn)
        } else if career.fans == nil, career.trust < Balance.careerRenewalTrust, game.myPlayer?.contract.seasonsLeft ?? 9 <= 1 {
            notice(String(localized: "감독 신뢰가 낮습니다. 계약이 끝나면 재계약 제안을 받지 못할 수 있습니다."), Theme.warn)
        }
    }

    private func notice(_ text: String, _ color: Color) -> some View {
        Banner(text: text, color: color, icon: "envelope.fill", action: goToCareer)
    }

    private func appearanceNote(_ me: Player) -> String? {
        guard game.nextMatch() != nil, !game.isMatchLive else { return nil }
        if (me.suspendedMatches ?? 0) > 0 { return String(localized: "출장 정지로 다음 리그 경기에 나서지 못합니다.") }
        if let plan = game.careerFootballPlan {
            if plan.starts { return String(localized: "다음 경기에 선발로 나섭니다.") }
            if let minute = plan.subMinute { return String(localized: "다음 경기는 벤치에서 시작합니다. \(minute)분쯤 교체로 들어갑니다.") }
            return String(localized: "다음 경기는 벤치입니다. 골키퍼는 교체로 나오지 않습니다.")
        }
        if let plan = game.careerBasketballPlan {
            if plan.starts { return String(localized: "다음 경기에 선발로 나섭니다.") }
            return String(localized: "다음 경기는 벤치에서 시작합니다. \(plan.minutes ?? 0)분쯤 뜁니다 (감독 신뢰가 오르면 늘어납니다).")
        }
        if let plan = game.careerDuelPlan {
            guard let index = plan.setIndex else {
                return String(localized: "다음 경기는 출전 순서에 들지 못했습니다. 네 경기에 한 번은 세트를 받습니다.")
            }
            return plan.isAce ? String(localized: "다음 경기에 에이스로 1세트에 나갑니다. 1 : 1이면 에이스 결정전에도 나갑니다.")
                : String(localized: "다음 경기 \(index + 1)세트에 나갑니다.")
        }
        switch me.position {
        case .starter:
            return game.careerStartsNextMatch ? String(localized: "다음 경기에 선발로 등판합니다.") : String(localized: "다음 경기는 등판하지 않는 날입니다. 팀 경기를 지켜봅니다.")
        case .reliever, .closer:
            return String(localized: "선발이 내려가면 가장 먼저 올라옵니다.")
        default:
            return String(localized: "다음 경기에 선발로 나섭니다.")
        }
    }
}
