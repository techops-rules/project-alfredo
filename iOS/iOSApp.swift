import SwiftUI

struct iOSMainView: View {
    @Environment(\.theme) private var theme
    @State private var isBooted = false

    private let splashUpdates = [
        "Direct Mode ready for multi-turn Alfredo chats",
        "Kiosk voice + agent bridge synced with native surfaces",
        "Session handoff notes refreshed for Claude/Codex coordination"
    ]

    var body: some View {
        Group {
            if isBooted {
                DashboardView()
                    .transition(.opacity)
            } else {
                BootScreen(updateNotes: splashUpdates) {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isBooted = true
                    }
                }
            }
        }
    }
}
