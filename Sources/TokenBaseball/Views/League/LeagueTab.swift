import SwiftUI
import TokenBaseballCore

struct LeagueTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game
    @State private var tier: LeagueTier?
    @State private var openTeam: TeamID?

    private var shown: LeagueTier { tier ?? game.userTier }

    var body: some View {
        VStack(spacing: 10) {
            Picker("리그", selection: Binding(get: { shown }, set: { tier = $0; openTeam = nil })) {
                ForEach(LeagueTier.allCases, id: \.self) { Text("\($0.rawValue)부").tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Card(shown.localizedDisplayName(for: game.sport), trailing: String(localized: "강도 범위 \(Int(Balance.strengthRange(shown).lowerBound))~\(Int(Balance.strengthRange(shown).upperBound))")) {
                standings
            }
            if shown == game.userTier { promotion }
            if let cup = game.cup { CupCard(game: game, cup: cup) }
            if game.sport == .duel, let career = game.career, !career.retired { DuelCircuitCard(game: game, career: career) }
            leaders
            awards
        }
    }

    /// 축구의 승격·강등 규칙 한 줄. 20팀 리그는 세 팀, 그보다 작은 리그는 두 팀이 오르내린다.
    private func footballRuleText(teams: Int) -> String {
        let direct = Balance.footballAutoPromotions(teams: teams)
        let up = direct == 1 ? String(localized: "1위는") : String(localized: "1~\(direct)위는")
        return String(localized: "\(up) 자동 승격, \(direct + 1)~\(direct + 4)위는 승격 플레이오프(한 팀 승격), 맨 아래 \(direct + 1)팀(\(teams - direct)~\(teams)위)은 자동 강등.")
    }

    private var standings: some View {
        let rows = game.rankedStandings(shown)
        return VStack(spacing: 4) {
            HStack {
                Text("순위").frame(width: 28, alignment: .leading)
                Text("팀")
                Spacer()
                Text("승").frame(width: 24)
                if game.sport.hasDraws { Text("무").frame(width: 24) }
                Text("패").frame(width: 24)
                if game.sport.ranksByPoints {
                    Text("득실").frame(width: 32, alignment: .trailing)
                    Text("승점").frame(width: 32, alignment: .trailing)
                } else {
                    Text("승률").frame(width: 44, alignment: .trailing)
                }
            }
            .note()
            ForEach(Array(rows.enumerated()), id: \.element.teamID) { index, row in
                let team = game.teams[row.teamID]
                Button {
                    openTeam = openTeam == team.id ? nil : team.id
                } label: {
                    HStack {
                        Text("\(index + 1)").frame(width: 28, alignment: .leading)
                        Text(team.name).fontWeight(team.isUser ? .bold : .regular).lineLimit(1)
                        Spacer()
                        Text("\(row.wins)").frame(width: 24)
                        if game.sport.hasDraws { Text("\(row.draws)").frame(width: 24) }
                        Text("\(row.losses)").frame(width: 24)
                        if game.sport.ranksByPoints {
                            Text("\(row.goalDifference > 0 ? "+" : "")\(row.goalDifference)").frame(width: 32, alignment: .trailing)
                            Text("\(row.points)").bold().frame(width: 32, alignment: .trailing)
                        } else {
                            Text(String(format: "%.3f", row.winRate)).frame(width: 44, alignment: .trailing)
                        }
                    }
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(team.isUser || (game.isCareer && team.id == game.userTeamID) ? Color.accentColor : .primary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if openTeam == team.id { TeamDetail(game: game, team: team, row: row) }
            }
            Text(game.sport.usesEnglishPromotion
                ? "팀을 누르면 선수단을 볼 수 있습니다. \(footballRuleText(teams: rows.count))"
                : "팀을 누르면 선수단을 볼 수 있습니다. 1위는 자동 승격, 2위와 3위는 와일드카드를 거쳐 윗 리그 9위와 승강 플레이오프, 10위는 자동 강등.").note()
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var promotion: some View {
        if !game.isCareer, let level = game.promotionStadiumRequirement {
            Card(String(localized: "승격 조건: 구장 등급")) {
                KeyValueRow(
                    key: String(localized: "필요한 경기장"), value: "Lv\(game.userTeam.stadiumLevel) / Lv\(level)",
                    valueColor: game.userTeam.stadiumLevel >= level ? Theme.win : Theme.loss)
                if game.userTeam.stadiumLevel >= level {
                    Label("구장 등급을 채웠습니다. 순위만으로 승격이 정해집니다.", systemImage: "checkmark.seal.fill")
                        .font(.callout).foregroundStyle(Theme.win)
                } else {
                    Text("시즌이 끝날 때까지 경기장을 Lv\(level)로 올리지 못하면, 1위를 해도 승격 자격이 다음 순위 팀으로 넘어갑니다. 구단 탭에서 업그레이드합니다.").note()
                }
                Text("신청은 필요 없습니다. \(footballRuleText(teams: game.rankedStandings(game.userTier).count)) 플레이오프는 준결승 두 경기 합산, 결승 중립 구장 단판입니다.").note()
            }
        } else if !game.isCareer, let requirement = game.promotionRequirement {
            Card(String(localized: "승강 플레이오프 신청")) {
                KeyValueRow(
                    key: String(localized: "필요 인지도"), value: "\(Int(game.userTeam.fame)) / \(Int(requirement.fame))",
                    valueColor: game.userTeam.fame >= requirement.fame ? Theme.win : Theme.loss)
                KeyValueRow(key: String(localized: "신청비"), value: DisplayFormat.money(requirement.fee))
                KeyValueRow(key: String(localized: "신청 마감"), value: String(localized: "\(Balance.applicationDeadlineRound)라운드 (지금 \(game.round)라운드 종료)"))
                if game.appliedForPromotion {
                    Label("신청 완료. 시즌이 끝났을 때 1위면 자동 승격, 2위나 3위면 와일드카드를 거쳐 승강 플레이오프에 나갑니다.", systemImage: "checkmark.seal.fill")
                        .font(.callout).foregroundStyle(Theme.win)
                } else {
                    Button("신청하기") { model.perform { try $0.applyForPromotion() } }
                        .disabled(game.phase != .regular)
                    Text("신청하지 않으면 1~3위를 해도 승격할 수 없고, 그 자리는 다음 순위 팀이 이어받습니다.").note()
                }
            }
        }
    }

    private var leaders: some View {
        Card(String(localized: "기록 순위")) {
            let groups = game.leaders(shown, count: 3)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .top), GridItem(.flexible(), alignment: .top)], spacing: 10) {
                ForEach(groups, id: \.title) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.title).font(.caption.bold())
                        if group.rows.isEmpty { Text("—").note() }
                        ForEach(Array(group.rows.enumerated()), id: \.offset) { _, row in
                            HStack {
                                Text(row.playerName).fontWeight(row.isMine ? .bold : .regular).lineLimit(1)
                                Spacer()
                                Text(row.value).monospacedDigit()
                            }
                            .font(.caption)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder private var awards: some View {
        let list = game.awards.filter { $0.tier == shown }
        if !list.isEmpty {
            Card(String(localized: "지난 시즌 시상")) {
                ForEach(Array(list.enumerated()), id: \.offset) { _, award in
                    KeyValueRow(
                        key: "\(award.title) · \(award.playerName) (\(award.teamName))", value: award.detail,
                        valueColor: award.isMine ? Theme.win : .primary)
                }
            }
        }
    }
}
