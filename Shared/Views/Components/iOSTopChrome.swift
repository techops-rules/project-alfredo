import SwiftUI

#if os(iOS)
struct iOSTopChrome: View {
    @Environment(\.theme) private var theme
    let onHamburger: () -> Void
    @State private var now = Date()

    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var timeString: String {
        let f = DateFormatter()
        f.dateFormat = "h:mm"
        return f.string(from: now)
    }

    private var dateString: String {
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: now)
    }

    var body: some View {
        HStack(spacing: 0) {
            // Left: compact time + date
            HStack(spacing: 6) {
                Text(timeString)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textEmphasis)

                Text(dateString.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
            }

            Spacer()

            // Center: status dots
            StatusDotsView(monitor: ConnectionMonitor.shared)

            Spacer()

            // Right: hamburger menu
            Button(action: onHamburger) {
                VStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1)
                            .fill(ThemeManager.textSecondary)
                            .frame(width: 14, height: 1.5)
                    }
                }
                .frame(width: 32, height: 28)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(ThemeManager.surface.opacity(0.8))
        .background(.ultraThinMaterial.opacity(0.5))
        .overlay(
            Rectangle()
                .fill(theme.accentBorder.opacity(0.3))
                .frame(height: 1),
            alignment: .bottom
        )
        .onReceive(timer) { _ in now = Date() }
    }
}
#endif
