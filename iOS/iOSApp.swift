import SwiftUI

struct iOSMainView: View {
    @Environment(\.theme) private var theme
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
    }
}
