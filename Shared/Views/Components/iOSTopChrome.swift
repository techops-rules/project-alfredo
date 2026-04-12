import SwiftUI

#if os(iOS)
struct iOSTopChrome: View {
    @Environment(\.theme) private var theme

    let modeLabel: String
    let summary: String?
    let isEditMode: Bool
    let onSync: () -> Void
    let onHamburger: () -> Void

    @State private var now = Date()
    private let monitor = ConnectionMonitor.shared
    private let timer = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return formatter.string(from: now)
    }

    private var dateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE MMM d"
        return formatter.string(from: now).uppercased()
    }

    private var statusLabel: String {
        if monitor.connectors.allSatisfy({ $0.status == .connected }) {
            return "LIVE"
        }
        if monitor.connectors.contains(where: { $0.status == .checking }) {
            return "CHECKING"
        }
        if monitor.connectors.contains(where: { $0.status == .connected }) {
            return "PARTIAL"
        }
        if monitor.connectors.allSatisfy({ $0.status == .notConfigured }) {
            return "SETUP"
        }
        return "OFFLINE"
    }

    private var statusColor: Color {
        switch statusLabel {
        case "LIVE": return ThemeManager.success
        case "CHECKING": return ThemeManager.warning
        case "PARTIAL": return ThemeManager.warning
        case "SETUP": return ThemeManager.textSecondary
        default: return ThemeManager.danger
        }
    }

    private var secondaryLabel: String {
        if isEditMode {
            return "EDIT CANVAS"
        }
        if let summary, !summary.isEmpty {
            return summary.uppercased()
        }
        return "READY FOR WHAT NEXT"
    }

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(timeString)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundColor(ThemeManager.textEmphasis)

                    Text(dateString)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                        .tracking(1.4)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    chromeButton(label: "SYNC", systemName: "arrow.clockwise", action: onSync)
                    chromeButton(label: "MENU", systemName: "line.3.horizontal", action: onHamburger)
                }
            }

            HStack(spacing: 8) {
                chromeChip(
                    label: modeLabel.uppercased(),
                    tone: theme.accentFull.opacity(0.12),
                    border: theme.accentBorder
                )

                HStack(spacing: 6) {
                    StatusDotsView(monitor: monitor)
                    Text(statusLabel)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundColor(statusColor)
                        .tracking(1.2)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(statusColor.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 999)
                        .strokeBorder(statusColor.opacity(0.35), lineWidth: 1)
                )
                .clipShape(Capsule())

                Text(secondaryLabel)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundColor(isEditMode ? ThemeManager.warning : ThemeManager.textPrimary)
                    .tracking(0.9)
                    .lineLimit(1)
                    .minimumScaleFactor(0.72)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(ThemeManager.surface.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: 999)
                            .strokeBorder(theme.accentBorder.opacity(0.55), lineWidth: 1)
                    )
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 12)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background(
            LinearGradient(
                colors: [
                    ThemeManager.background.opacity(0.96),
                    ThemeManager.surface.opacity(0.9)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .background(.ultraThinMaterial.opacity(0.45))
        .overlay(
            Rectangle()
                .fill(theme.accentBorder.opacity(0.32))
                .frame(height: 1),
            alignment: .bottom
        )
        .onReceive(timer) { _ in
            now = Date()
        }
    }

    private func chromeButton(label: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 3) {
                Image(systemName: systemName)
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .tracking(1)
            }
            .foregroundColor(theme.accentFull)
            .frame(width: 42, height: 34)
            .background(ThemeManager.surface.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(theme.accentBorder.opacity(0.7), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private func chromeChip(label: String, tone: Color, border: Color) -> some View {
        Text(label)
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundColor(theme.accentFull)
            .tracking(1.2)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(tone)
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .strokeBorder(border.opacity(0.7), lineWidth: 1)
            )
            .clipShape(Capsule())
    }
}
#endif
