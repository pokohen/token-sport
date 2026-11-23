import SwiftUI
import TokenBaseballCore

/// 선수 만들기의 "출신 (연고지)": 제목과 도시 고르기.
struct HometownPicker: View {
    @Binding var selection: String

    var body: some View {
        Text("출신 (연고지)").font(.callout.weight(.medium))
        ChoiceGrid(items: NameGenerator.userCities, selection: $selection, columns: 4) { $0 }
    }
}
