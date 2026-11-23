import Foundation

/// 축구 전술 성향. 슈팅 기회와 실점 위험이 함께 오르내린다.
public enum Tactic: String, Codable, CaseIterable, Sendable {
    case attacking = "공격적", balanced = "균형", defensive = "수비적"

    /// 공격 쪽 능력에 더하는 값. 수비 쪽에는 같은 크기를 뺀다.
    var attackShift: Double {
        switch self {
        case .attacking: 4
        case .balanced: 0
        case .defensive: -4
        }
    }
}

/// 축구 포메이션. 줄마다 서는 인원이 달라지고, 강한 곳과 약한 곳이 생긴다.
public enum Formation: String, Codable, CaseIterable, Sendable {
    case f442 = "4-4-2", f433 = "4-3-3", f4231 = "4-2-3-1", f41212 = "4-1-2-1-2"
    case f352 = "3-5-2", f343 = "3-4-3", f532 = "5-3-2"

    public var label: String { rawValue }

    /// 수비, 미드필더, 공격 인원.
    public var shape: (defenders: Int, midfielders: Int, forwards: Int) {
        switch self {
        case .f442, .f41212: (4, 4, 2)
        case .f433: (4, 3, 3)
        case .f4231: (4, 5, 1)
        case .f352: (3, 5, 2)
        case .f343: (3, 4, 3)
        case .f532: (5, 3, 2)
        }
    }

    /// 열한 자리. 골키퍼 → 수비 → 미드필더 → 공격 순.
    public var slots: [Position] {
        let s = shape
        return [.goalkeeper] + Array(repeating: .defender, count: s.defenders)
            + Array(repeating: .midfielder, count: s.midfielders) + Array(repeating: .forward, count: s.forwards)
    }

    /// 중원 싸움에 더하는 값 (공격할 때도 수비할 때도).
    var midfieldShift: Double {
        switch self {
        case .f433: -2
        case .f4231: 2
        case .f41212: 2
        case .f352: 3
        case .f532: -2
        case .f442, .f343: 0
        }
    }

    /// 상대 진영에서 기회를 만들 때 더하는 값.
    var attackShift: Double {
        switch self {
        case .f433: 3
        case .f4231: -4
        case .f343: 5
        default: 0
        }
    }

    /// 우리 진영에서 막을 때 더하는 값.
    var defenseShift: Double {
        switch self {
        case .f41212: -5
        case .f352: -6
        case .f343: -5
        case .f532: 4
        default: 0
        }
    }

    public var summary: String {
        switch self {
        case .f442: "기본형. 강한 곳도 약한 곳도 없습니다."
        case .f433: "공격수 3명. 상대 진영에서 기회를 더 만들지만 중원 싸움에서 밀립니다."
        case .f4231: "미드필더 5명에 원톱. 중원을 잡지만 상대 진영에서 기회가 줄어듭니다."
        case .f41212: "다이아몬드 중원. 중원을 장악하지만 측면이 비어 우리 진영 수비가 약해집니다."
        case .f352: "수비수 3명에 미드필더 5명. 중원이 가장 강하지만 우리 진영 수비가 가장 약합니다."
        case .f343: "수비수 3명에 공격수 3명. 기회를 가장 많이 만들지만 뒤가 열립니다."
        case .f532: "수비수 5명. 우리 진영 수비가 단단하지만 중원 싸움에서 밀립니다."
        }
    }
}
