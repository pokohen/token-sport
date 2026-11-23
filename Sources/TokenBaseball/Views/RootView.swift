import SwiftUI
import TokenBaseballCore

enum AppTab: String, CaseIterable {
    case home = "홈", match = "경기", league = "리그", club = "구단", players = "선수", settings = "설정"

    /// 선수 모드에서는 구단 탭 자리가 훈련, 선수 탭 자리가 커리어다.
    func icon(_ sport: Sport, career: Bool = false) -> String {
        switch self {
        case .home: "house.fill"
        case .match: sport == .football ? "soccerball" : sport == .basketball ? "basketball.fill" : "baseball.fill"
        case .league: "list.number"
        case .club: career ? "dumbbell.fill" : "building.2.fill"
        case .players: career ? "person.text.rectangle.fill" : "person.3.fill"
        case .settings: "gearshape.fill"
        }
    }

    func title(career: Bool) -> String {
        guard career else { return rawValue }
        switch self {
        case .club: return "훈련"
        case .players: return "커리어"
        default: return rawValue
        }
    }
}

struct RootView: View {
    @EnvironmentObject var model: AppModel
    @State private var tab = AppTab.home

    var body: some View {
        Group {
            if let error = model.loadError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.largeTitle).foregroundStyle(Theme.warn)
                    Text(error).multilineTextAlignment(.center).textSelection(.enabled)
                    Text("파일을 옮기거나 지운 뒤 앱을 다시 실행해 주세요. 덮어쓰지 않도록 게임을 시작하지 않았습니다.").note()
                        .multilineTextAlignment(.center)
                    // 한 모드의 파일이 깨져도 다른 모드는 계속 할 수 있어야 한다.
                    ForEach(model.selectableSlots.filter { $0 != model.slot }, id: \.self) { other in
                        Button("\(other.label)\(other.isCareer ? "로" : "으로") 가기") { model.switchSlot(to: other) }
                    }
                    Button("종료") { NSApplication.shared.terminate(nil) }
                }
                .padding(24)
            } else if let game = model.game, game.career?.retired == true {
                CareerRetiredView(game: game)
            } else if let game = model.game, !game.isBankrupt {
                main(game)
            } else {
                OnboardingView(bankrupt: model.game?.isBankrupt == true)
            }
        }
        // 설정에서 야구/축구를 바꾸면 그 모드의 홈부터 보여 준다.
        .onChange(of: model.slot) { _, _ in tab = .home }
        .onAppear { model.setPopoverVisible(true) }
        .onDisappear { model.setPopoverVisible(false) }
    }

    private func main(_ game: Game) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 2) {
                ForEach(AppTab.allCases, id: \.self) { item in
                    Button {
                        tab = item
                        model.message = nil
                    } label: {
                        VStack(spacing: 2) {
                            Image(systemName: item.icon(game.sport, career: game.isCareer)).font(.system(size: 14))
                            Text(item.title(career: game.isCareer)).font(.caption2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .foregroundStyle(tab == item ? Color.accentColor : .secondary)
                        .background(tab == item ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 8))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            Divider()

            if let update = model.update, tab != .settings {
                Button {
                    tab = .settings
                } label: {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text(update.headline).font(.callout)
                        Spacer()
                        Text("설정에서 보기").font(.caption)
                        Image(systemName: "chevron.right").font(.caption)
                    }
                    .padding(8)
                    .foregroundStyle(.white)
                    .background(Color.accentColor)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }

            if let message = model.message {
                HStack {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(message).font(.callout)
                    Spacer()
                    Button { model.message = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
                }
                .padding(8)
                .foregroundStyle(.white)
                .background(Theme.loss)
            }

            ScrollView {
                TabContent(tab: tab, game: game, startMatchTab: { tab = .match }, openTab: { tab = $0 })
                    .padding(12)
            }
        }
    }
}

/// 탭 내용. 스크롤 없이 그릴 수 있게 따로 둔다 (화면 확인용 스냅샷에서도 쓴다).
struct TabContent: View {
    let tab: AppTab
    let game: Game
    var startMatchTab: () -> Void = {}
    var openTab: (AppTab) -> Void = { _ in }

    var body: some View {
        switch tab {
        case .home:
            if game.isCareer {
                CareerHomeTab(game: game, goToMatch: startMatchTab, goToCareer: { openTab(.players) })
            } else {
                HomeTab(game: game, goToMatch: startMatchTab)
            }
        case .match: MatchTab(game: game)
        case .league: LeagueTab(game: game)
        case .club:
            if game.isCareer { CareerTrainingTab(game: game) } else { ClubTab(game: game) }
        case .players:
            if game.isCareer { CareerTab(game: game) } else { PlayersTab(game: game) }
        case .settings: SettingsTab(game: game)
        }
    }
}
