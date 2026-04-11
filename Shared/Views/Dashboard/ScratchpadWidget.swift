import SwiftUI

struct ScratchpadWidget: View {
    let lines: [String]
    let onAddLine: (String) -> Void

    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics
    @State private var blinkVisible = true

    private let blinkTimer = Timer.publish(every: 0.53, on: .main, in: .common).autoconnect()

    var body: some View {
        WidgetShell(title: "SCRATCH.TXT", badge: "\(lines.count)", zone: "right") {
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                ScrollView {
                    VStack(alignment: .leading, spacing: max(3, metrics.rowSpacing - 2)) {
                        ForEach(Array(lines.prefix(metrics.primaryListLimit).enumerated()), id: \.offset) { _, line in
                            HStack(spacing: 6) {
                                Text(">")
                                    .font(.system(size: metrics.bodyFontSize, weight: .bold, design: .monospaced))
                                    .foregroundColor(theme.accentFull)
                                Text(line)
                                    .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                                    .foregroundColor(ThemeManager.textPrimary)
                                    .lineLimit(metrics.isCompact ? 1 : 2)
                            }
                        }

                        if lines.count > metrics.primaryListLimit {
                            Text("+ \(lines.count - metrics.primaryListLimit) more lines")
                                .font(.system(size: metrics.captionFontSize, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary)
                        }

                        HStack(spacing: 6) {
                            Text(">")
                                .font(.system(size: metrics.bodyFontSize, weight: .bold, design: .monospaced))
                                .foregroundColor(theme.accentFull)
                            Rectangle()
                                .fill(theme.accentFull)
                                .frame(width: 8, height: metrics.bodyFontSize + 2)
                                .opacity(blinkVisible ? 1 : 0)
                        }
                    }
                }

                QuickCaptureField(placeholder: metrics.isCompact ? "capture..." : "capture something...", onSubmit: onAddLine)
            }
            .onReceive(blinkTimer) { _ in blinkVisible.toggle() }
        }
    }
}
