import SwiftUI

struct ProgressDots: View {
    let percent: Int
    let dotCount: Int = 5

    @Environment(\.theme) private var theme

    private var filledCount: Int {
        Int(round(Double(percent) / 100.0 * Double(dotCount)))
    }

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<dotCount, id: \.self) { i in
                Circle()
                    .fill(i < filledCount ? theme.accentFull : theme.accentTrack)
                    .frame(width: 8, height: 8)
            }
        }
    }
}
