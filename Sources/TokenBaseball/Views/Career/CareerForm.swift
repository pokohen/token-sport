import SwiftUI
import TokenBaseballCore

/// 내 선수를 만들 때 정하는 값을 고르는 화면 조각. 첫 시작과 은퇴 뒤 새 선수 만들기에 같이 쓴다.
struct CareerForm: View {
    @Binding var setup: CareerSetup
    var sport: Sport = .baseball
    @State private var pitcher = false

    var body: some View {
        switch sport {
        case .football: football
        case .basketball: basketball
        case .baseball: baseball
        }
    }

    private var basketball: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("선수 이름", text: $setup.name).textFieldStyle(.roundedBorder)
            ChoiceGrid(items: CareerSetup.basketballPositions, selection: $setup.position, columns: 3) { $0.label }
            Text(positionNote).note()
            startPoints
            Text("출신 (연고지)").font(.callout.weight(.medium))
            ChoiceGrid(items: NameGenerator.userCities, selection: $setup.hometown, columns: 4) { $0 }
        }
        .font(.callout)
        .onChange(of: setup.position) { setup.points = [:] }
        .onAppear { if setup.position.sport != .basketball { setup.position = .shootingGuard } }
    }

    private var football: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("선수 이름", text: $setup.name).textFieldStyle(.roundedBorder)
            ChoiceGrid(items: CareerSetup.footballPositions, selection: $setup.position, columns: 4) { $0.label }
            Text(positionNote).note()
            startPoints
            Text("출신 (연고지)").font(.callout.weight(.medium))
            ChoiceGrid(items: NameGenerator.userCities, selection: $setup.hometown, columns: 4) { $0 }
        }
        .font(.callout)
        .onChange(of: setup.position) { setup.points = [:] }
        .onAppear { if setup.position.sport != .football { setup.position = .forward } }
    }

    private var baseball: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("선수 이름", text: $setup.name).textFieldStyle(.roundedBorder)

            Picker("유형", selection: Binding(
                get: { pitcher },
                set: { value in
                    pitcher = value
                    setup.position = value ? .starter : .shortstop
                })) {
                Text("타자").tag(false)
                Text("투수").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            let positions = pitcher ? CareerSetup.pitcherPositions : CareerSetup.batterPositions
            ChoiceGrid(items: positions, selection: $setup.position, columns: pitcher ? 2 : 3) { $0.label }
            Text(positionNote).note()
            startPoints

            HStack {
                Picker("타석", selection: $setup.bats) {
                    Text("우타").tag(Hand.right)
                    Text("좌타").tag(Hand.left)
                }
                Picker("투구", selection: $setup.throwsHand) {
                    Text("우투").tag(Hand.right)
                    Text("좌투").tag(Hand.left)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Text("출신 (연고지)").font(.callout.weight(.medium))
            ChoiceGrid(items: NameGenerator.userCities, selection: $setup.hometown, columns: 4) { $0 }
        }
        .font(.callout)
        .onChange(of: setup.position) { setup.points = [:] }
        .onAppear {
            if setup.position.sport != .baseball { setup.position = .shortstop }
            pitcher = setup.position.isPitcher
        }
    }

    /// 시작 포인트: 내 포지션의 능력치에 직접 나눠 넣는다.
    private var startPoints: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("시작 포인트").font(.callout.weight(.medium))
                Spacer()
                Text("남은 포인트 \(setup.pointsLeft) / \(Balance.careerStartPoints)")
                    .font(.callout.monospacedDigit())
                    .foregroundStyle(setup.pointsLeft > 0 ? Color.accentColor : Color.secondary)
            }
            ForEach(Attributes.weights(for: setup.position).map(\.0), id: \.self) { key in
                let count = setup.points[key] ?? 0
                HStack(spacing: 8) {
                    Text(key.label)
                    Spacer()
                    Text(count > 0 ? "+\(Int(Double(count) * Balance.careerStartPointValue))" : "—")
                        .monospacedDigit()
                        .foregroundStyle(count > 0 ? Color.accentColor : Color.secondary)
                    Button { setup.points[key] = count - 1 } label: { Image(systemName: "minus") }
                        .disabled(count <= 0)
                        .accessibilityLabel("\(key.label) 포인트 빼기")
                    Button { setup.points[key] = count + 1 } label: { Image(systemName: "plus") }
                        .disabled(setup.pointsLeft <= 0 || count >= Balance.careerStartPointsPerStat)
                        .accessibilityLabel("\(key.label) 포인트 넣기")
                }
                .controlSize(.small)
            }
            Text("포인트 하나에 그 능력치가 +\(Int(Balance.careerStartPointValue)) 오릅니다 (능력치 하나에 \(Balance.careerStartPointsPerStat)개까지). 시작 능력과 성장 한계는 타고난 재능이라 선수마다 다르게 정해지고, 입단하면 스카우트 평가로 알려 줍니다.").note()
        }
    }

    private var positionNote: String {
        switch setup.position {
        case .starter:
            "선발 투수: 쉬는 날을 채우면 반드시 선발로 나옵니다 (시민 리그는 3경기에 한 번, 3부부터는 5경기에 한 번). 나오지 않는 날은 팀 경기를 지켜보고, 대신 훈련을 한 번 더 합니다."
        case .reliever:
            "불펜 투수: 선발이 내려가면 가장 먼저 올라옵니다. 자주 나오지만 짧게 던지고, 많이 던졌거나 연투한 다음 날은 쉽니다."
        case .goalkeeper:
            "골키퍼: 교체로 나올 수 없어서, 주전을 따내기 전에는 친선 경기와 네 경기 중 한 경기에만 나옵니다. 주전까지 가장 오래 걸리는 포지션입니다. 골키핑이 능력의 70%입니다."
        case .defender:
            "수비수: 수비·피지컬·스피드가 중요합니다. 무실점 경기와 공을 뺏는 장면으로 평점을 받습니다."
        case .midfielder:
            "미드필더: 패스·드리블이 중요합니다. 공을 앞으로 운반하고 도움을 올립니다."
        case .forward:
            "공격수: 슈팅·드리블·스피드가 중요합니다. 골로 평가받습니다. 주전이 아니면 벤치에서 시작해 후반에 교체로 들어갑니다."
        case .pointGuard:
            "포인트 가드: 공을 운반하고 공격을 조립합니다. 패스·드리블이 중요하고, 어시스트로 평가받습니다."
        case .shootingGuard:
            "슈팅 가드: 팀의 주 득점원입니다. 3점슛·슛이 중요하고, 득점으로 평가받습니다."
        case .smallForward:
            "스몰 포워드: 안팎에서 고르게 뜁니다. 슛·3점슛·수비가 중요합니다."
        case .powerForward:
            "파워 포워드: 골밑에서 싸웁니다. 리바운드·슛·피지컬이 중요하고, 리바운드로 평가받습니다."
        case .center5:
            "센터: 골밑을 지킵니다. 리바운드·피지컬·수비가 중요하고, 블록과 리바운드가 쌓입니다. 포지션마다 선발은 한 명이고, 선발이 아니어도 감독 신뢰만큼 출전 시간을 받습니다."
        case .designated:
            "지명타자: 매 경기 타석에 서고 수비는 하지 않습니다. 컨택·파워·선구안·주력만 훈련합니다."
        default:
            "타자: 매 경기 선발로 나옵니다. 포지션은 커리어 중에 바꿀 수 없습니다."
        }
    }
}
