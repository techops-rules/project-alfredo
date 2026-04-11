import SwiftUI

struct MacApp: View {
    @State private var isBooted = false

    var body: some View {
        Group {
            if isBooted {
                DashboardView()
                    .transition(.opacity)
            } else {
                BootScreen {
                    withAnimation(.easeInOut(duration: 0.4)) {
                        isBooted = true
                    }
                }
            }
        }
        .frame(minWidth: 1200, minHeight: 700)
        .environment(\.theme, ThemeManager.shared)
    }
}
