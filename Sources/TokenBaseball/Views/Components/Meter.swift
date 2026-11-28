import SwiftUI
import TokenBaseballCore

/// 0~100 값을 막대로 보여 준다.
struct Meter: View {
    let label: String
    let value: Double
    var color: Color = .accentColor

    var body: some View {
        HStack(spacing: 8) {
            Text(label).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true).frame(width: 64, alignment: .leading)
            Bar(fraction: value / 100, color: color)
            Text("\(Int(value.rounded()))").monospacedDigit().frame(width: 28, alignment: .trailing)
        }
        .font(.callout)
    }
}

/// 채워지는 막대.
struct Bar: View {
    let fraction: Double
    var color: Color = .accentColor

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.secondary.opacity(0.2))
                Capsule().fill(color).frame(width: proxy.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: 6)
    }
}
