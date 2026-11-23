import SwiftUI
import TokenBaseballCore

/// 첫 실행: 환영 → 연고지 → 팀 이름 → 색상·엠블럼 → 시작. 파산 뒤 새 구단을 만들 때도 쓴다.
struct OnboardingView: View {
    @EnvironmentObject var model: AppModel
    let bankrupt: Bool

    @State private var step: Int
    @State private var city = NameGenerator.userCities[0]
    @State private var name = ""
    @State private var colorIndex = 0
    @State private var emblemIndex = 0
    @State private var slot = SaveSlot.baseballPlayer
    @State private var career = CareerSetup(name: "", position: .shortstop)
    private var sport: Sport { slot.sport }
    /// 구단이 아니라 선수를 만드는 중인지.
    private var makingPlayer: Bool { fixedSport == nil && slot.isCareer }

    /// 파산 뒤 다시 만들 때는 종목을 바꿀 수 없다 (세계가 그대로 이어진다).
    init(bankrupt: Bool, step: Int = 0) {
        self.bankrupt = bankrupt
        _step = State(initialValue: step)
    }

    private var fixedSport: Sport? { bankrupt ? model.game?.sport : nil }
    private var chosen: Sport { fixedSport ?? sport }
    private var defaultName: String { chosen == .football ? "\(city) 시민 FC" : "\(city) 시민 야구단" }
    private var finalName: String { name.trimmingCharacters(in: .whitespaces).isEmpty ? defaultName : name }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // 선수 만들기는 고를 것이 많아 창 높이를 넘을 수 있으니 스크롤할 수 있게 한다.
            if step == 0 { welcome } else { ScrollView { form.frame(maxWidth: .infinity, alignment: .leading) } }
            if let message = model.message {
                Text(message).font(.callout).foregroundStyle(Theme.loss)
            }
            Spacer()
            HStack {
                if step > 0 { Button("이전") { step -= step == 2 && fixedSport != nil ? 2 : 1 } }
                Spacer()
                if step == 1, fixedSport == nil, model.hasSave(slot: slot) {
                    Button("\(slot.label) 이어서 하기") { model.switchSlot(to: slot) }
                        .keyboardShortcut(.defaultAction)
                } else if makingPlayer, step == 2 {
                    if career.pointsLeft > 0 {
                        Text("시작 포인트가 \(career.pointsLeft)개 남았습니다").note()
                    }
                    Button("커리어 시작") { model.createCareer(career) }
                        .keyboardShortcut(.defaultAction)
                } else if step < 4 {
                    // 종목이 정해져 있으면 종목 고르기는 건너뛴다.
                    Button("다음") { step += step == 0 && fixedSport != nil ? 2 : 1 }.keyboardShortcut(.defaultAction)
                } else {
                    Button("구단 창단") {
                        model.createClub(
                            .init(city: city, name: finalName, colorIndex: colorIndex, emblemIndex: emblemIndex),
                            sport: chosen)
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(24)
        .onAppear {
            // 숨겨 둔 모드가 골라져 있으면 (처음 실행 등) 야구 선수부터 보여 준다.
            slot = model.selectableSlots.contains(model.slot) || fixedSport != nil ? model.slot : .baseballPlayer
        }
    }

    private var welcome: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                if fixedSport != .football { Image(systemName: fixedSport == nil ? "figure.baseball" : "baseball.fill") }
                if fixedSport != .baseball { Image(systemName: fixedSport == nil ? "figure.soccer" : "soccerball") }
                if fixedSport == nil { Image(systemName: "figure.basketball") }
            }
            .font(.system(size: 40)).foregroundStyle(Color.accentColor)
            if bankrupt {
                Text("팀을 새로 키워주세요").font(.title2.bold())
                Text("구단이 파산해 해체되었습니다. 세계는 그대로 이어지고, 6부 시민 아마추어에서 새 시민 구단으로 다시 시작합니다.")
                if let last = model.game?.hallOfFame.last {
                    Card("명예의 전당") {
                        Text("\(last.name) · \(last.foundedSeason)~\(last.endedSeason)시즌 · 최고 \(last.bestTier.displayName)")
                        if let star = last.star { Text("간판 선수 \(star)").note() }
                    }
                }
            } else {
                Text("Token Sports").font(.title2.bold())
                Text("평소처럼 AI 코딩을 하면 쓴 토큰이 훈련 포인트로 쌓입니다. 야구, 축구, 농구 선수 가운데 한 명이 되어, 그 포인트로 훈련하고 경기에 나서며 6부 시민 구단에서 1부 프로 리그의 스타까지 올라가 보세요.")
                Card("토큰 사용량을 읽는 곳") {
                    Text(model.sources.claudeCode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.sources.codex.root.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.sources.gemini.root.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text(model.sources.opencode.root.path).font(.caption.monospaced()).textSelection(.enabled)
                    Text("이 컴퓨터 안에서만 읽습니다. 외부로 보내지 않습니다. 설치 이전 사용량은 세지 않습니다.").note()
                }
            }
            Text("KBO를 비롯한 실제 리그·구단과 무관한 비공식 팬 프로젝트입니다.").note()
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(makingPlayer && step == 2
                ? "내 선수를 만들어 주세요"
                : ["", "무엇을 할지 골라 주세요", "연고지를 골라 주세요", "팀 이름을 정해 주세요", "팀 색상과 엠블럼"][step]).font(.title3.bold())
            switch step {
            case 1:
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2), spacing: 8) {
                    ForEach(model.selectableSlots, id: \.self) { item in
                        Button { slot = item } label: {
                            VStack(spacing: 6) {
                                BallIcon(sport: item.sport, size: 36)
                                Text(item.label).font(.headline)
                                Text(model.hasSave(slot: item) ? "저장되어 있음"
                                    : item == .football ? "구단 경영 · 승점제" : item == .footballPlayer ? "선수 한 명의 커리어"
                                    : item == .basketballPlayer ? "가드·포워드·센터의 커리어"
                                    : item.isCareer ? "타자·투수 한 명의 커리어" : "구단 경영 · 승률제").note()
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(slot == item ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.accentColor, lineWidth: slot == item ? 2 : 0))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(item.label)
                    }
                }
                Text(slot.isCareer
                    ? "\(slot.label): 16세에 6부 시민 구단에 입단해, 토큰으로 훈련하고 더 높은 리그로 올라가 1부 프로 리그의 스타가 되는 것이 목표입니다. 구단은 모두 CPU가 운영합니다."
                    : "구단과 선수는 따로 저장됩니다. 나중에 설정에서 다른 모드로 바꿔 하나 더 만들 수 있습니다. 한 번에 하나만 토큰을 받습니다.").note()
            case 2 where makingPlayer:
                CareerForm(setup: $career, sport: slot.sport)
                Text("\(LeagueTier.citizenAmateur.displayName) 리그의 시민 구단에 입단합니다. 시작 훈련 포인트 \(Format.tokens(FundsLedger.startingFunds)) P.").note()
            case 2:
                ChoiceGrid(items: NameGenerator.userCities, selection: $city, columns: 4) { $0 }
            case 3:
                TextField(defaultName, text: $name).textFieldStyle(.roundedBorder)
                Text("비워 두면 \"\(defaultName)\"이 됩니다. 나중에 설정에서 바꿀 수 있습니다.").note()
            default:
                HStack(spacing: 8) {
                    ForEach(Theme.teamColors.indices, id: \.self) { index in
                        Circle().fill(Theme.teamColors[index]).frame(width: 30, height: 30)
                            .overlay(Circle().stroke(.primary, lineWidth: colorIndex == index ? 3 : 0))
                            .onTapGesture { colorIndex = index }
                            .accessibilityLabel(Theme.teamColorNames[index])
                    }
                }
                HStack(spacing: 8) {
                    ForEach(Theme.emblems.indices, id: \.self) { index in
                        Image(systemName: Theme.emblems[index]).font(.title2)
                            .frame(width: 40, height: 40)
                            .background(emblemIndex == index ? Color.accentColor.opacity(0.25) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .onTapGesture { emblemIndex = index }
                            .accessibilityLabel(Theme.emblemNames[index])
                    }
                }
                Card {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle().fill(Theme.teamColors[colorIndex])
                            Image(systemName: Theme.emblems[emblemIndex]).font(.title2.bold()).foregroundStyle(.white)
                        }
                        .frame(width: 48, height: 48)
                        VStack(alignment: .leading) {
                            Text(finalName).font(.headline)
                            Text("\(LeagueTier.citizenAmateur.displayName) · \(chosen.label) · 선수 \(chosen == .football ? 16 : 14)명 · 시작 자금 ₩\(FundsLedger.startingFunds.formatted())").note()
                        }
                    }
                }
            }
        }
    }
}
