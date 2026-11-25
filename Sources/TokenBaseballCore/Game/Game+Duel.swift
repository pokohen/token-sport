import Foundation

// e스포츠 1:1 대전의 팀 경기. 지금은 화면 없이 치르는 경기만 있다.
// 선수 모드의 경기(중계, 세트 배정, 기록)는 다음 단계에서 붙인다 (→ docs/10-esports.md 만드는 순서 4).

extension Game {
    /// 1:1 대전 팀 경기를 화면 없이 끝까지 치르고 세트 점수를 돌려준다.
    /// 에이스를 뺀 선수들이 차례로 한 세트씩 나가고, 마지막 세트까지 가면 에이스가 에이스 결정전에 나간다.
    /// 두 팀 중 하나라도 세 명이 안 되면 nil.
    func quietDuelMatch(home: TeamID, away: TeamID, bestOf: Int = DuelLineupBuilder.setsPerMatch, seed: UInt64)
        -> (home: Int, away: Int)?
    {
        guard let homeOrder = DuelLineupBuilder.build(team: teams[home], players: players),
              let awayOrder = DuelLineupBuilder.build(team: teams[away], players: players)
        else { return nil }
        var rng = SeededRNG(seed: seed)
        let need = bestOf / 2 + 1
        var score = (home: 0, away: 0)
        var set = 0
        while score.home < need, score.away < need {
            let decider = score.home == need - 1 && score.away == need - 1
            func pick(_ order: [PlayerID]) -> DuelPlayer {
                let id = decider ? order[0] : Array(order.dropFirst())[set % (order.count - 1)]
                return DuelPlayer(players[id]!)
            }
            var duel = DuelSet(
                first: pick(homeOrder), second: pick(awayOrder), map: rng.pick(DuelMap.pool),
                stakes: decider ? .ace : .regular, seed: rng.next())
            duel.runToEnd()
            if duel.winner == 0 { score.home += 1 } else { score.away += 1 }
            set += 1
        }
        return score
    }
}
