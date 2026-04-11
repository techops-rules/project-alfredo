import SwiftUI

struct ConnectionStatusBar: View {
    @Environment(\.theme) private var theme

    private let monitor = ConnectionMonitor.shared
    @State private var visible = true
    @State private var expanded = false
    @State private var hideTask: Task<Void, Never>?

    var body: some View {
        if visible || monitor.status != .connected {
            Button(action: { withAnimation(.spring(response: 0.3)) { expanded.toggle() } }) {
                HStack(spacing: 6) {
                    statusDot
                    Text(statusText)
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary)

                    if expanded, let lastSeen = monitor.lastSeen {
                        Text("\u{00B7}")
                            .foregroundColor(ThemeManager.textSecondary.opacity(0.4))
                        let formatter = RelativeDateTimeFormatter()
                        Text(formatter.localizedString(for: lastSeen, relativeTo: .now))
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary.opacity(0.6))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background(ThemeManager.surface.opacity(0.85))
                .clipShape(Capsule())
                .overlay(Capsule().stroke(statusBorderColor.opacity(0.3), lineWidth: 0.5))
            }
            .buttonStyle(.plain)
            .onChange(of: monitor.status) { _, newStatus in
                if newStatus == .connected {
                    scheduleAutoHide()
                } else {
                    hideTask?.cancel()
                    visible = true
                }
            }
            .onAppear {
                if monitor.status == .connected {
                    scheduleAutoHide()
                }
            }
        }
    }

    @ViewBuilder
    private var statusDot: some View {
        Circle()
            .fill(statusDotColor)
            .frame(width: 5, height: 5)
            .opacity(monitor.status == .checking ? 0.6 : 1)
    }

    private var statusText: String {
        switch monitor.status {
        case .connected: return "connected"
        case .disconnected: return "offline \u{2014} cached"
        case .checking: return "connecting..."
        case .notConfigured: return "not configured"
        }
    }

    private var statusDotColor: Color {
        switch monitor.status {
        case .connected: return ThemeManager.success
        case .disconnected, .notConfigured: return ThemeManager.warning
        case .checking: return ThemeManager.warning
        }
    }

    private var statusBorderColor: Color {
        switch monitor.status {
        case .connected: return ThemeManager.success
        case .disconnected, .notConfigured, .checking: return ThemeManager.warning
        }
    }

    private func scheduleAutoHide() {
        hideTask?.cancel()
        visible = true
        hideTask = Task {
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { visible = false }
        }
    }
}
