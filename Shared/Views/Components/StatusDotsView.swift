import SwiftUI

struct StatusDotsView: View {
    @Environment(\.theme) private var theme
    let monitor: ConnectionMonitor
    @State private var showPopover = false

    private var hasIssue: Bool {
        monitor.connectors.contains { $0.status == .disconnected }
    }

    var body: some View {
        HStack(spacing: 5) {
            ForEach(monitor.connectors, id: \.name) { connector in
                Circle()
                    .fill(dotColor(connector.status))
                    .frame(width: 6, height: 6)
            }
        }
        .onTapGesture {
            if hasIssue {
                showPopover = true
            }
        }
        .popover(isPresented: $showPopover) {
            statusPopover
        }
    }

    private func dotColor(_ status: ConnectionStatus) -> Color {
        switch status {
        case .connected:     return ThemeManager.success
        case .disconnected:  return ThemeManager.danger
        case .checking:      return ThemeManager.warning
        case .notConfigured: return ThemeManager.textSecondary.opacity(0.4)
        }
    }

    private var statusPopover: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("CONNECTIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentFull)
                .tracking(2)

            ForEach(monitor.connectors, id: \.name) { connector in
                HStack(spacing: 8) {
                    Circle()
                        .fill(dotColor(connector.status))
                        .frame(width: 6, height: 6)
                    Text(connector.name.uppercased())
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textPrimary)
                    Spacer()
                    Text(statusLabel(connector.status))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)
                }
            }

            Divider().opacity(0.3)

            Button {
                monitor.checkAll()
                showPopover = false
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 9))
                    Text("REFRESH")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1)
                }
                .foregroundColor(theme.accentFull)
                .padding(.vertical, 4)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .frame(width: 200)
        .background(ThemeManager.surface)
    }

    private func statusLabel(_ status: ConnectionStatus) -> String {
        switch status {
        case .connected:     return "OK"
        case .disconnected:  return "DOWN"
        case .checking:      return "..."
        case .notConfigured: return "N/A"
        }
    }
}
