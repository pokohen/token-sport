import Foundation

/// 축구 경기 엔진: 슈팅과 세트피스.
extension FootballMatch {
    // MARK: 슈팅

    mutating func shoot(_ events: inout [MatchEvent]) {
        guard let shooterIndex = pickAttacker({
            Self.slotWeight($0.slot, forward: 3, midfielder: 1.4, defender: 0.35) * Self.skillShare($0.shooting)
                * ($0.style?.shotWeight ?? 1)
        }) else { return }
        var assistIndex: Int?
        if rng.chance(0.7) {
            assistIndex = pickAttacker(excluding: shooterIndex) {
                Self.slotWeight($0.slot, forward: 1.5, midfielder: 2, defender: 0.8) * Self.skillShare($0.passing)
                    * ($0.style?.assistWeight ?? 1)
            }
        }
        let shooter = attacking.players[shooterIndex]
        // 욕심내기: 무리한 슈팅이 섞여 정확도가 떨어진다.
        let power = shootingValue(shooter) - (shooter.style == .greedy ? 5 : 0)
        attacking.shots += 1
        attacking.players[shooterIndex].line.shots += 1

        let wall = defending.mean([.defender]) { $0.tackling } - defending.shortHanded
        if rng.chance(clamp(0.24 * exp((wall - power) / 100), 0.08, 0.5)) {
            let blocker = name(of: defending, in: [.defender], credit: \.clearances)
            if rng.chance(0.45) {
                say(&events, .play, "\(shooter.name) 슛! \(blocker) 몸으로 막아 코너킥")
                awardCorner()
            } else {
                say(&events, .play, "\(shooter.name) 슛! \(blocker) 막아냅니다")
                flip(to: 0)
            }
            return
        }
        // 골문 안으로 가는지는 슈팅과 수비 압박으로 정한다. 골키퍼의 실력은 다음 단계(막아내는가)에만 들어간다.
        // (여기에 골키퍼를 넣으면 좋은 골키퍼가 막은 공이 선방이 아니라 "빗나감"으로 잡힌다.)
        guard rng.chance(clamp(0.41 + (power - wall) / 300, 0.2, 0.65)) else {
            say(&events, .play, "\(shooter.name) \(rng.pick(Self.missLines))")
            flip(to: 0)
            return
        }
        attacking.shotsOnTarget += 1
        attacking.players[shooterIndex].line.shotsOnTarget += 1
        let keeping = keepingValue()
        if rng.chance(clamp(0.36 * exp((power - keeping) / Self.keeperSpread), 0.06, 0.6)) {
            score(shooterIndex, assist: assistIndex, how: rng.pick(Self.goalLines), &events)
        } else {
            saved(by: shooter.name, &events)
        }
    }

    mutating func saved(by shooterName: String, _ events: inout [MatchEvent]) {
        var keeperName = "골키퍼"
        if let index = defending.keeperIndex {
            defending.players[index].line.saves += 1
            keeperName = defending.players[index].name
        }
        if rng.chance(0.3) {
            say(&events, .play, "\(shooterName) 유효 슈팅! \(keeperName) 쳐내서 코너킥")
            awardCorner()
        } else {
            say(&events, .play, "\(shooterName) 슈팅, \(keeperName) \(rng.pick(Self.saveLines))")
            flip(to: 0)
        }
    }

    mutating func awardCorner() {
        attacking.corners += 1
        zone = 2
        pending = .corner
    }

    mutating func score(_ scorerIndex: Int, assist: Int?, how: String, _ events: inout [MatchEvent]) {
        attacking.goals += 1
        attacking.players[scorerIndex].line.goals += 1
        var text = "골! \(attacking.shortName) \(attacking.players[scorerIndex].name) \(how)"
        if let assist {
            attacking.players[assist].line.assists += 1
            text += " (도움 \(attacking.players[assist].name))"
        }
        if let keeper = defending.keeperIndex { defending.players[keeper].line.conceded += 1 }
        say(&events, .score, "\(text) — \(scoreText)")
        // 실점한 팀의 킥오프
        flip(to: 1)
    }

    // MARK: 세트피스

    mutating func resolve(_ piece: SetPiece, _ events: inout [MatchEvent]) {
        switch piece {
        case .corner:
            let taker = holder([.midfielder])
            if rng.chance(0.16) {
                header(from: taker, what: "코너킥", &events)
            } else if rng.chance(0.7) {
                say(&events, .play, "\(attacking.shortName) \(taker) 코너킥, 수비가 걷어냅니다")
                flip(to: 0)
            } else {
                say(&events, .play, "\(attacking.shortName) \(taker) 코너킥, 흘러나온 공을 다시 잡습니다")
            }
        case .freeKick:
            guard let takerIndex = bestTaker() else { return }
            let taker = attacking.players[takerIndex]
            if rng.chance(0.35) {
                attacking.shots += 1
                attacking.players[takerIndex].line.shots += 1
                let power = shootingValue(taker) + (taker.traits.contains(.setPiece) ? 8 : 0)
                let wall = defending.mean([.defender]) { $0.tackling }
                if rng.chance(clamp(0.36 + (power - wall) / 300, 0.15, 0.6)) {
                    attacking.shotsOnTarget += 1
                    attacking.players[takerIndex].line.shotsOnTarget += 1
                    if rng.chance(clamp(0.20 * exp((power - keepingValue()) / Self.keeperSpread), 0.04, 0.45)) {
                        score(takerIndex, assist: nil, how: "프리킥 직접 골!", &events)
                    } else {
                        saved(by: "\(taker.name) 프리킥", &events)
                    }
                } else {
                    say(&events, .play, "\(taker.name) 프리킥, 벽을 넘겼지만 골대를 벗어납니다")
                    flip(to: 0)
                }
            } else if rng.chance(0.14) {
                header(from: taker.name, what: "프리킥", &events)
            } else {
                say(&events, .play, "\(taker.name) 프리킥을 올렸지만 수비가 먼저 걷어냅니다")
                flip(to: 0)
            }
        case .penalty:
            guard let takerIndex = bestTaker() else { return }
            let taker = attacking.players[takerIndex]
            attacking.shots += 1
            attacking.players[takerIndex].line.shots += 1
            let power = shootingValue(taker) + (taker.traits.contains(.setPiece) ? 8 : 0)
            if rng.chance(clamp(0.76 + (power - keepingValue(penalty: true)) / 250, 0.55, 0.92)) {
                attacking.shotsOnTarget += 1
                attacking.players[takerIndex].line.shotsOnTarget += 1
                score(takerIndex, assist: nil, how: "페널티킥 성공!", &events)
            } else if rng.chance(0.7) {
                attacking.shotsOnTarget += 1
                attacking.players[takerIndex].line.shotsOnTarget += 1
                var keeperName = "골키퍼"
                if let index = defending.keeperIndex {
                    defending.players[index].line.saves += 1
                    keeperName = defending.players[index].name
                }
                say(&events, .play, "\(taker.name) 페널티킥, \(keeperName) 막았습니다!")
                flip(to: 0)
            } else {
                say(&events, .play, "\(taker.name) 페널티킥, 골대를 벗어납니다!")
                flip(to: 0)
            }
        }
    }

    func bestTaker() -> Int? {
        let side = attacking
        return side.players.indices
            .filter { side.players[$0].isOnPitch && side.players[$0].slot != .goalkeeper }
            .max {
                let a = side.players[$0], b = side.players[$1]
                let av = a.shooting + (a.traits.contains(.setPiece) ? 8 : 0)
                let bv = b.shooting + (b.traits.contains(.setPiece) ? 8 : 0)
                return (av, -a.playerID) < (bv, -b.playerID)
            }
    }

    mutating func header(from taker: String, what: String, _ events: inout [MatchEvent]) {
        guard let index = pickAttacker({
            Self.slotWeight($0.slot, forward: 2, midfielder: 1, defender: 1.5) * (0.4 + $0.physical / 100)
        }) else { return }
        let player = attacking.players[index]
        attacking.shots += 1
        attacking.players[index].line.shots += 1
        let power = (player.physical * 0.6 + player.shooting * 0.4) * player.fatigue + bonus(home: homeHasBall)
        guard rng.chance(0.42) else {
            say(&events, .play, "\(taker) \(what), \(player.name) 헤더! 골대 위로 넘어갑니다")
            flip(to: 0)
            return
        }
        attacking.shotsOnTarget += 1
        attacking.players[index].line.shotsOnTarget += 1
        if rng.chance(clamp(0.28 * exp((power - keepingValue()) / Self.keeperSpread), 0.06, 0.55)) {
            let assist = attacking.players.firstIndex { $0.isOnPitch && $0.name == taker && $0.playerID != player.playerID }
            score(index, assist: assist, how: "헤더 골!", &events)
        } else {
            saved(by: "\(player.name) 헤더", &events)
        }
    }
}
