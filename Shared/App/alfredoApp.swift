import SwiftUI
#if os(iOS)
import UIKit
#endif

// MARK: - Shared notification names

extension Notification.Name {
    static let showEventBriefing = Notification.Name("alfredo.showEventBriefing")
}

// MARK: - iOS App Delegate (push notification registration)

#if os(iOS)
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[APNs] Device token: \(token)")
        PushTokenService.shared.register(token: token)
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] Registration failed: \(error.localizedDescription)")
    }
}
#endif

@main
struct alfredoApp: App {
    #if os(macOS)
    @State private var menuBarManager = MenuBarManager()
    #else
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    #endif
    private let updateService = UpdateService.shared
    private let briefingScheduler = BriefingScheduler.shared
    private let voiceEventService = VoiceEventService.shared

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            MacApp()
                .onAppear {
                    menuBarManager.setup()
                    // updateService.startChecking()
                    briefingScheduler.start()
                    voiceEventService.start()
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
                    // updateService.startChecking()
                    briefingScheduler.start()
                    voiceEventService.start()
                }
        }
        #endif
    }
}
