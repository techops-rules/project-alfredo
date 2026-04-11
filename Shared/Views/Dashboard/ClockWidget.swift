import SwiftUI

struct ClockWidget: View {
    @Environment(\.theme) private var theme
    @State private var now = Date()
    @State private var colonVisible = true

    private let timer = Timer.publish(every: 0.53, on: .main, in: .common).autoconnect()
    private let secondTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var hourMinute: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: now)
    }

    private var seconds: String {
        let f = DateFormatter()
        f.dateFormat = "ss"
        return f.string(from: now)
    }

    private var ampm: String {
        let f = DateFormatter()
        f.dateFormat = "a"
        return f.string(from: now)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "EEE . MMM dd . yyyy"
        return f.string(from: now).uppercased()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(hourMinute)
                    .font(.system(size: 42, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textEmphasis)

                Text(seconds)
                    .font(.system(size: 20, design: .monospaced))
                    .foregroundColor(theme.accentFull.opacity(0.6))

                Text(ampm)
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .padding(.leading, 4)
            }

            Text(dateString)
                .font(.system(size: theme.fontSize, weight: .medium, design: .monospaced))
                .foregroundColor(theme.accentFull)
                .tracking(2)
        }
        .onReceive(secondTimer) { _ in
            now = Date()
        }
    }
}
