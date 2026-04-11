import SwiftUI

struct ScratchpadWidget: View {
    let lines: [String]
    let onAddLine: (String) -> Void

    @Environment(\.theme) private var theme
    @State private var blinkVisible = true

    private let blinkTimer = Timer.publish(every: 0.53, on: .main, in: .common).autoconnect()

    var body: some View {
        WidgetShell(title: "SCRATCH.TXT", badge: "\(lines.count)", zone: "right") {
            VStack(alignment: .leading, spacing: 6) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                            HStack(spacing: 6) {
                                Text(">")
                                    .font(.system(size: theme.fontSize, weight: .bold, design: .monospaced))
                                    .foregroundColor(theme.accentFull)
                                Text(line)
                                    .font(.system(size: theme.fontSize, design: .monospaced))
                                    .foregroundColor(ThemeManager.textPrimary)
                            }
                        }

                        // Blinking cursor
                        HStack(spacing: 6) {
                            Text(">")
                                .font(.system(size: theme.fontSize, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.accentFull)
                            Rectangle()
                                .fill(theme.accentFull)
                                .frame(width: 8, height: theme.fontSize + 2)
                                .opacity(blinkVisible ? 1 : 0)
                        }
                    }
                }

                QuickCaptureField(placeholder: "capture something...", onSubmit: onAddLine)
            }
            .onReceive(blinkTimer) { _ in blinkVisible.toggle() }
        }
    }
}
