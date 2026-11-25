import SwiftUI
import TokenBaseballCore

/// 선수 모드에서 기록을 한 줄 글로 만든다.
enum CareerText {
    static func batting(_ line: BattingLine) -> String {
        "\(line.games)경기 타율 \(String(format: "%.3f", line.average)) \(line.homeRuns)홈런 \(line.runsBattedIn)타점"
    }

    static func pitching(_ line: PitchingLine) -> String {
        "\(line.games)경기 \(line.wins)승 \(line.losses)패 \(line.saves)세 평균자책점 \(String(format: "%.2f", line.era))"
    }

    static func football(_ line: FootballLine, keeper: Bool) -> String {
        keeper
            ? "\(line.games)경기 무실점 \(line.cleanSheets)경기 선방 \(line.saves) 실점 \(line.conceded)"
            : "\(line.games)경기 \(line.goals)골 \(line.assists)도움 슈팅 \(line.shots)"
    }

    static func basketball(_ line: BasketballLine) -> String {
        func average(_ value: Double) -> String { String(format: "%.1f", value) }
        return "\(line.games)경기 평균 \(average(line.pointsPerGame))점 \(average(line.reboundsPerGame))리바운드 \(average(line.assistsPerGame))도움"
    }

    /// "세트 12승 5패 (71%) · 에이스 결정전 3승 1패".
    static func duel(_ line: DuelLine) -> String {
        guard line.sets > 0 else { return "아직 세트 기록이 없습니다" }
        var text = "세트 \(line.setWins)승 \(line.setLosses)패 (\(Int((line.winRate * 100).rounded()))%)"
        if line.aceWins + line.aceLosses > 0 { text += " · 에이스 결정전 \(line.aceWins)승 \(line.aceLosses)패" }
        return text
    }

    /// 종목과 포지션에 맞는 기록 한 줄.
    static func record(
        _ me: Player, batting: BattingLine, pitching: PitchingLine, football: FootballLine?,
        basketball: BasketballLine? = nil
    ) -> String {
        switch me.position.sport {
        case .basketball: return CareerText.basketball(basketball ?? BasketballLine())
        case .football: return CareerText.football(football ?? FootballLine(), keeper: me.position == .goalkeeper)
        case .baseball: return me.isPitcher ? CareerText.pitching(pitching) : CareerText.batting(batting)
        case .duel: return CareerText.duel(me.duel ?? DuelLine())
        }
    }

    static func rating(_ value: Double?) -> String { value.map { String(format: "%.2f", $0) } ?? "—" }

}
