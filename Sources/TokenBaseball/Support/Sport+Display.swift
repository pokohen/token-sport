import TokenBaseballCore

/// 화면에서 종목마다 다르게 보여 주는 것. 모두 빠짐없는 switch라서, 새 종목을 넣으면 여기부터 정하게 된다.
extension Sport {
    /// 경기 탭 아이콘 (SF Symbols).
    var matchSymbol: String {
        switch self {
        case .baseball: "baseball.fill"
        case .football: "soccerball"
        case .basketball: "basketball.fill"
        case .duel: "computermouse.fill"
        }
    }

    /// 상단바 공 그림의 이름 (손쉬운 사용).
    var ballName: String {
        switch self {
        case .baseball: "야구공"
        case .football: "축구공"
        case .basketball: "농구공"
        case .duel: "마우스"
        }
    }

    /// 내 팀이 득점했을 때 보내는 알림의 제목. 농구는 득점이 워낙 잦아서 알리지 않는다.
    var scoreAlertTitle: String? {
        switch self {
        case .baseball: "득점!"
        case .football: "골!"
        // e스포츠는 세트가 끝날 때만 알린다.
        case .basketball, .duel: nil
        }
    }

    /// 득점 장면에서 중계를 잠깐 멈춘다. 농구는 득점이 워낙 잦아서 멈추지 않는다.
    var pausesOnScore: Bool {
        switch self {
        case .baseball, .football: true
        case .basketball, .duel: false
        }
    }

    /// 알림 설정에 적는 알림 종류. 농구는 득점 알림이 없다.
    var notificationKinds: String {
        switch self {
        case .baseball: "경기 가능, 득점, 경기 종료"
        case .football: "경기 가능, 골, 경기 종료"
        case .basketball, .duel: "경기 가능, 경기 종료"
        }
    }

    /// 선수 모드 경기 전에 플레이 스타일을 고른다.
    var hasPlayStyles: Bool {
        switch self {
        case .football, .basketball, .duel: true
        case .baseball: false
        }
    }


    /// 설정 탭 안내문: 무엇과 무관한지.
    var leagueDisclaimer: String {
        switch self {
        case .baseball: "KBO 및 각 구단과 무관한"
        case .football, .basketball: "실제 리그·구단과 무관한"
        case .duel: "실제 게임·리그·게임단과 무관한"
        }
    }

    /// 구단 경영의 상단바 훈련 그림 (훈련소 3단계부터 웨이트가 더해진다).
    /// 경기 중에는 훈련 그림 대신 공이 나온다 (→ MenuBarLabel).
    var clubDrills: [Sprites.Drill] {
        switch self {
        case .baseball: [.batting, .pitching, .fielding, .running]
        case .football: [.dribbling, .shooting, .keeping, .running]
        case .basketball: [.bouncing, .jumpShot, .running]
        // 1:1 대전은 구단 모드가 없다. 전용 그림은 화면 단계에서 그린다 (다른 종목 그림을 빌리지 않는다).
        case .duel: []
        }
    }
}

extension Player {
    /// 선수 모드의 상단바 훈련 그림: 내 선수가 하는 훈련만.
    var trainingDrills: [Sprites.Drill] {
        switch position.sport {
        case .baseball: isPitcher ? [.pitching, .running, .weights] : [.batting, .fielding, .running, .weights]
        case .football: position == .goalkeeper ? [.keeping, .running, .weights] : [.dribbling, .shooting, .running, .weights]
        case .basketball: [.bouncing, .jumpShot, .running, .weights]
        // 전용 그림(손풀기, 리플레이)은 화면 단계에서 그린다 (→ docs/10-esports.md "화면").
        case .duel: []
        }
    }

    /// 던지는 손과 치는 손 ("우투좌타"). 야구 선수만 있다.
    var handedness: String? {
        switch position.sport {
        case .baseball: "\(throwsHand.rawValue)투\(bats.rawValue)타"
        case .football, .basketball, .duel: nil
        }
    }
}
