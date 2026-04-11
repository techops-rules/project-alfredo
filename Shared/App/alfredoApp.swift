import SwiftUI

// MARK: - Shared notification names

extension Notification.Name {
    static let showEventBriefing = Notification.Name("alfredo.showEventBriefing")
}

@main
struct alfredoApp: App {
    #if os(macOS)
    @State private var menuBarManager = MenuBarManager()
    #endif
    private let updateService = UpdateService.shared
    private let briefingScheduler = BriefingScheduler.shared

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacApp()
                .onAppear {
                    menuBarManager.setup()
                    updateService.startChecking()
                    briefingScheduler.start()
                }
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1400, height: 800)
        #else
        WindowGroup {
            iOSMainView()
                .environment(\.theme, ThemeManager.shared)
                .preferredColorScheme(.dark)
                .onAppear {
                    updateService.startChecking()
                    briefingScheduler.start()
                }
        }
        #endif
    }
}
