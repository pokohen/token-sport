import SwiftUI
import TokenBaseballCore

/// 다른 저장 칸(야구 선수, 축구 선수)으로 옮기는 버튼들.
struct SlotSwitcher: View {
    @EnvironmentObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(model.selectableSlots.filter { $0 != model.slot }, id: \.self) { slot in
                HStack {
                    BallIcon(sport: slot.sport)
                    Text(slot.localizedLabel)
                    Text(model.hasSave(slot: slot) ? "저장되어 있음" : "아직 없음").note()
                    Spacer()
                    Button(model.hasSave(slot: slot) ? "이어서 하기" : "새로 만들기") { model.switchSlot(to: slot) }
                }
            }
            Text("모드마다 따로 저장됩니다. 한 번에 하나만 진행하고, 쉬는 쪽은 그동안 쓴 토큰을 받지 않으며 경기 기회도 쌓이지 않습니다.").note()
        }
        .font(.callout)
    }
}
