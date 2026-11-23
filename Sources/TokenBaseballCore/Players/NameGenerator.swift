import Foundation

/// 선수·구단 이름을 자동으로 만든다. 실제 선수·구단·학교·기업 이름은 쓰지 않는다.
public enum NameGenerator {
    static let surnames = [
        "김", "이", "박", "최", "정", "강", "조", "윤", "장", "임", "한", "오", "서", "신", "권",
        "황", "안", "송", "전", "홍", "유", "고", "문", "양", "손", "배", "백", "허", "남", "심",
        "노", "하", "곽", "성", "차", "주", "우", "구", "민", "진", "나", "지", "엄", "채", "원",
    ]
    static let givenFirst = [
        "민", "서", "지", "도", "하", "준", "예", "시", "주", "현", "승", "우", "태", "성", "재",
        "동", "상", "영", "정", "진", "건", "규", "기", "병", "석", "용", "종", "창", "한", "형",
    ]
    static let givenSecond = [
        "준", "우", "현", "호", "민", "석", "훈", "수", "진", "혁", "환", "빈", "찬", "율", "원",
        "섭", "철", "식", "근", "겸", "결", "솔", "록", "범", "표", "욱", "흠", "탁", "엽", "국",
    ]

    /// 걸러낼 이름: KBO 현역·주요 은퇴 선수와 겹치는 이름은 만들지 않는다.
    static let blocked: Set<String> = [
        "이승엽", "이대호", "류현진", "김광현", "양현종", "박병호", "이정후", "김하성", "선동열", "박찬호",
        "추신수", "이종범", "양의지", "최정", "강백호", "김도영", "문동주", "안우진", "오승환", "구자욱",
        "나성범", "손아섭", "김현수", "박용택", "이병규", "장종훈", "최동원", "김태균", "정근우", "이용규",
        "홍창기", "노시환", "원태인", "고우석", "임찬규", "박건우", "황재균", "전준우", "강민호", "최형우",
        "김재환", "박민우", "오지환", "김혜성", "송성문", "문보경", "박세웅", "곽빈", "김원중", "정우람",
    ]

    static let foreignNames = [
        "알렉스 리드", "브랜든 콜", "마르코 산토스", "루이스 베가", "타일러 헤이즈", "카를로스 메나",
        "제이크 모로", "닉 페레즈", "오스틴 브룩", "라파엘 누네즈", "코디 웨스트", "미겔 로하",
        "데릭 스톤", "후안 카스트로", "잭 하퍼", "에릭 볼트",
    ]

    static let neighborhoods = [
        "행복동", "새마을동", "은행나무길", "솔밭동", "달맞이동", "물안개동", "까치마을", "별빛동",
        "시장통", "역전동", "강변동", "산성동", "포구동", "언덕마을", "느티나무골",
    ]
    static let jobs = [
        "치킨집 사장", "택배 기사", "체육 교사", "편의점 점장", "카센터 정비사", "횟집 주방장",
        "헬스 트레이너", "버스 기사", "개발자", "회사원", "소방관", "자영업자", "대학원생",
        "인쇄소 직원", "떡집 아들", "목수", "농부", "배달 라이더", "은행원", "공무원",
    ]
    static let proOrigins = [
        "고교 야구부 출신", "대학 야구부 출신", "실업팀 출신", "독립 리그 출신", "퓨처스 리그 출신",
        "유소년 야구 교실 출신", "입단 테스트 출신", "지역 리그 MVP 출신",
    ]

    /// 축구에서 걸러낼 이름: 널리 알려진 축구 선수와 겹치는 이름.
    static let blockedFootball: Set<String> = [
        "손흥민", "박지성", "이강인", "김민재", "차범근", "황희찬", "기성용", "이청용", "홍명보", "안정환",
        "조규성", "황의조", "이승우", "구자철", "박주영", "이동국", "김영권", "조현우", "김승규", "이재성",
        "황인범", "설영우", "정우영", "백승호", "양민혁", "배준호", "오현규", "주민규", "엄원상", "김진수",
        "이영표", "송종국", "유상철", "황선홍", "최용수", "김남일", "이천수", "이운재", "김병지", "고종수",
        "차두리", "박주호", "권창훈", "나상호", "송민규", "김문환", "정승현", "조유민", "홍현석", "이기제",
    ]
    static let footballOrigins = [
        "고교 축구부 출신", "대학 축구부 출신", "실업팀 출신", "하부 리그 출신", "유소년 클럽 출신",
        "풋살 리그 출신", "입단 테스트 출신", "지역 리그 득점왕 출신",
    ]

    /// 실제 농구 선수와 이름이 겹치지 않게 막는 이름.
    static let blockedBasketball: Set<String> = [
        "허재", "서장훈", "김주성", "양동근", "이상민", "문경은", "우지원", "현주엽", "김승현", "허웅", "허훈",
        "이정현", "김선형", "오세근", "최준용", "이대성", "전희철", "방성윤", "하승진", "라건아",
    ]
    static let basketballOrigins = [
        "고교 농구부 출신", "대학 농구부 출신", "실업팀 출신", "하부 리그 출신", "유소년 클럽 출신",
        "길거리 농구 출신", "입단 테스트 출신", "지역 리그 득점왕 출신",
    ]

    public static func playerName(_ rng: inout SeededRNG, sport: Sport = .baseball) -> String {
        while true {
            let name = rng.pick(surnames) + rng.pick(givenFirst) + rng.pick(givenSecond)
            let banned = sport == .baseball ? blocked : sport == .football ? blockedFootball : blockedBasketball
            if !banned.contains(name) { return name }
        }
    }

    public static func foreignName(_ rng: inout SeededRNG) -> String {
        rng.pick(foreignNames)
    }

    public static func origin(tier: LeagueTier, sport: Sport = .baseball, _ rng: inout SeededRNG) -> String {
        if tier.isCitizen {
            return "\(rng.pick(neighborhoods)) \(rng.pick(jobs))"
        }
        switch sport {
        case .football: return rng.pick(footballOrigins)
        case .basketball: return rng.pick(basketballOrigins)
        case .baseball: return rng.pick(proOrigins)
        }
    }

    // MARK: 구단

    /// 1부 프로 10팀: 연고지 + 애칭을 우리말로 옮긴 가상 구단.
    public static let proTeams: [(city: String, name: String)] = [
        ("광주", "광주 호랑이"), ("대구", "대구 사자"), ("부산", "부산 거인"), ("대전", "대전 독수리"),
        ("서울 잠실", "잠실 곰"), ("서울 잠실", "서울 쌍둥이"), ("서울 고척", "고척 영웅"),
        ("인천", "인천 상륙단"), ("수원", "수원 마법사"), ("창원", "창원 공룡"),
    ]

    /// 축구 1부 20팀: 연고지 + 우리말 애칭. 실제 구단을 떠올리게 하는 조합은 피했다.
    /// (앞의 열 팀은 리그가 10팀이던 때부터 있던 구단이다. 순서를 바꾸지 않는다.)
    public static let footballProTeams: [(city: String, name: String)] = [
        ("서울", "서울 한강 FC"), ("부산", "부산 등대"), ("인천", "인천 파도"), ("대구", "대구 태양"),
        ("광주", "광주 무등"), ("대전", "대전 한밭 FC"), ("울산", "울산 고래"), ("수원", "수원 성곽"),
        ("전주", "전주 한옥 FC"), ("강릉", "강릉 솔바람"),
        ("창원", "창원 갈매기"), ("청주", "청주 직지 FC"), ("춘천", "춘천 호반 FC"), ("제주", "제주 돌하르방"),
        ("포항", "포항 일출"), ("천안", "천안 삼거리 FC"), ("세종", "세종 한글 FC"), ("여수", "여수 밤바다"),
        ("경주", "경주 천년 FC"), ("안동", "안동 하회 FC"),
    ]

    /// 농구 1부 10팀: 연고지 + 우리말 애칭. 실제 구단을 떠올리게 하는 조합은 피했다.
    public static let basketballProTeams: [(city: String, name: String)] = [
        ("서울", "서울 남산 농구단"), ("부산", "부산 갈매기"), ("인천", "인천 등대"), ("대구", "대구 사과"),
        ("광주", "광주 빛고을"), ("대전", "대전 과학"), ("울산", "울산 돌고래"), ("수원", "수원 화성"),
        ("전주", "전주 비빔"), ("원주", "원주 치악"),
    ]

    public static func proTeams(_ sport: Sport) -> [(city: String, name: String)] {
        switch sport {
        case .baseball: proTeams
        case .football: footballProTeams
        case .basketball: basketballProTeams
        }
    }

    /// 구단을 만들 때 고를 수 있는 연고지.
    public static let userCities = [
        "서울", "부산", "대구", "광주", "대전", "인천", "수원", "창원", "울산", "청주",
        "전주", "춘천", "제주", "포항", "천안", "강릉",
    ]

    static let cpuCities = [
        "청주", "전주", "춘천", "제주", "포항", "천안", "강릉", "울산", "김해", "구미", "여수", "목포",
        "원주", "안동", "경주", "속초", "군산", "익산", "순천", "진주", "통영", "거제", "평택", "안산",
        "성남", "고양", "용인", "파주", "김포", "의정부", "남양주", "충주", "제천", "아산", "서산",
        "논산", "공주", "남원", "정읍", "나주", "광양", "밀양", "양산", "영주", "상주", "문경",
        "동해", "삼척", "태백", "서귀포", "세종", "이천", "여주", "양평", "가평",
    ]
    static let mascots = [
        "반달곰", "수달", "고래", "두루미", "매", "늑대", "여우", "황소", "산양", "돌고래",
        "까치", "올빼미", "표범", "물개", "사슴", "멧돼지", "불꽃", "파도", "번개", "돌풍",
    ]
    static let schoolWords = ["한빛", "새솔", "누리", "가온", "다솜", "푸른", "미르", "아라", "해담", "샛별"]
    static let industryWords = ["철강", "조선", "전자", "제지", "화학", "건설", "운수", "식품", "섬유", "기계"]

    /// 하위 리그 AI 구단 이름. `taken`에 없는 이름이 나올 때까지 만든다.
    public static func cpuTeam(
        tier: LeagueTier, taken: Set<String>, sport: Sport = .baseball, _ rng: inout SeededRNG
    ) -> (city: String, name: String) {
        let shortTaken = Set(taken.map(shortName))
        if sport == .football {
            for attempt in 0..<500 {
                let city = rng.pick(cpuCities)
                let name: String
                switch tier {
                case .pro, .semiPro:
                    name = rng.chance(0.5) ? "\(city) \(rng.pick(mascots))" : "\(city) \(rng.pick(mascots)) FC"
                case .amateur:
                    name = rng.chance(0.5)
                        ? "\(rng.pick(schoolWords))대학교"
                        : "\(city) \(rng.pick(industryWords)) 축구단"
                case .citizenPro:
                    name = rng.chance(0.6) ? "\(city) 시민 FC" : "\(city) \(rng.pick(mascots)) 클럽"
                case .citizenSemiPro:
                    name = rng.chance(0.6) ? "\(city) 시민 FC" : "\(city) 축구 동호회"
                case .citizenAmateur:
                    name = rng.chance(0.5) ? "\(city) 시민 FC" : "\(city) \(rng.pick(jobsClubs)) 축구회"
                }
                if !taken.contains(name), !shortTaken.contains(shortName(name)) || attempt > 300 {
                    return (city, name)
                }
            }
            return ("", "제\(taken.count + 1) 시민 FC")
        }
        if sport == .basketball {
            for attempt in 0..<500 {
                let city = rng.pick(cpuCities)
                let name: String
                switch tier {
                case .pro, .semiPro:
                    name = "\(city) \(rng.pick(mascots)) 농구단"
                case .amateur:
                    name = rng.chance(0.5)
                        ? "\(rng.pick(schoolWords))대학교 농구부"
                        : "\(city) \(rng.pick(industryWords)) 농구단"
                case .citizenPro:
                    name = rng.chance(0.6) ? "\(city) 시민 농구단" : "\(city) \(rng.pick(mascots)) 농구 클럽"
                case .citizenSemiPro:
                    name = rng.chance(0.6) ? "\(city) 시민 농구단" : "\(city) 농구 동호회"
                case .citizenAmateur:
                    name = rng.chance(0.5) ? "\(city) 시민 농구단" : "\(city) \(rng.pick(jobsClubs)) 농구회"
                }
                if !taken.contains(name), !shortTaken.contains(shortName(name)) || attempt > 300 {
                    return (city, name)
                }
            }
            return ("", "제\(taken.count + 1) 시민 농구단")
        }
        for attempt in 0..<500 {
            let city = rng.pick(cpuCities)
            let name: String
            switch tier {
            case .pro, .semiPro:
                name = "\(city) \(rng.pick(mascots))"
            case .amateur:
                name = rng.chance(0.5)
                    ? "\(rng.pick(schoolWords))대학교"
                    : "\(city) \(rng.pick(industryWords)) 야구부"
            case .citizenPro:
                name = rng.chance(0.6) ? "\(city) 시민 야구단" : "\(city) \(rng.pick(mascots)) 클럽"
            case .citizenSemiPro:
                name = rng.chance(0.6) ? "\(city) 시민 야구단" : "\(city) 야구 동호회"
            case .citizenAmateur:
                name = rng.chance(0.5) ? "\(city) 시민 야구단" : "\(city) \(rng.pick(jobsClubs)) 야구회"
            }
            // 짧은 이름(첫 단어)도 겹치지 않아야 중계에서 헷갈리지 않는다.
            if !taken.contains(name), !shortTaken.contains(shortName(name)) || attempt > 300 {
                return (city, name)
            }
        }
        let fallback = "제\(taken.count + 1) 시민 야구단"
        return ("", fallback)
    }

    static let jobsClubs = ["조기", "직장인", "상인", "청년", "동창", "주말", "한마음", "으뜸"]

    /// 중계와 상단바에 쓰는 짧은 이름 (첫 단어).
    public static func shortName(_ name: String) -> String {
        let first = name.split(separator: " ").first.map(String.init) ?? name
        return String(first.prefix(4))
    }
}
