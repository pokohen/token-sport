import SwiftUI
import TokenBaseballCore

struct MatchTab: View {
    @EnvironmentObject var model: AppModel
    let game: Game

    var body: some View {
        VStack(spacing: 10) {
            if game.isMatchLive { MatchSpeedCard() }
            if let live = game.live {
                LiveMatchView(
                    live: live, myName: game.myPlayer?.name, myPerformance: game.careerLivePerformance)
            } else if let live = game.liveFootball {
                FootballLiveView(live: live, myName: game.myPlayer?.name, myPerformance: game.careerLivePerformance)
            } else if let live = game.liveBasketball {
                BasketballLiveView(live: live, myName: game.myPlayer?.name, myPerformance: game.careerLivePerformance)
            } else {
                if let result = game.lastResult { LastResultCard(result: result) }
                NextMatchCard(game: game)
                schedule
                if game.sport != .baseball, game.isCareer {
                    PlayStyleCard(game: game)
                } else if game.sport == .football {
                    TacticCard(game: game)
                } else if game.isCareer {
                    Text("선수 모드에서는 라인업과 투수 운용을 감독이 정합니다. 경기 중에는 개입하지 않습니다.").note()
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    PolicyCard(game: game)
                }
            }
        }
    }

    @ViewBuilder private var schedule: some View {
        if game.phase == .regular, game.round < game.roundsPerSeason {
            Card("일정") {
                let upcoming = Array(game.schedules[game.userTier.index].enumerated())
                    .filter { $0.offset >= game.round }.prefix(6)
                ForEach(Array(upcoming), id: \.offset) { index, fixtures in
                    if let fixture = fixtures.first(where: { $0.involves(game.userTeamID) }) {
                        let opponent = game.teams[fixture.opponent(of: game.userTeamID)]
                        KeyValueRow(
                            key: "\(index + 1)라운드 · \(fixture.home == game.userTeamID ? "홈" : "원정")",
                            value: opponent.name)
                    }
                }
            }
        }
    }
}
