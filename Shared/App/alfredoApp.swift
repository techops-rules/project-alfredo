import SwiftUI

@main
struct alfredoApp: App {
    #if os(macOS)
    @State private var menuBarManager = MenuBarManager()
    #endif
    private let updateService = UpdateService.shared

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacApp()
                .onAppear {
                    menuBarManager.setup()
                    updateService.startChecking()
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
                }
        }
        #endif
    }
}
