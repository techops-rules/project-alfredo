import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

@Observable
final class UpdateService {
    static let shared = UpdateService()

    var availableVersion: String?
    var releaseNotes: String?
    var downloadURL: URL?
    var isDismissed = false

    var hasUpdate: Bool {
        availableVersion != nil && !isDismissed
    }

    /// URL pointing to a JSON manifest: { "version": "1.2.0", "notes": "...", "url": "..." }
    private let manifestURL = URL(string: "https://projectalfredo.app/version.json")!
    private let checkInterval: TimeInterval = 60 * 30 // 30 minutes
    private var timer: Timer?

    private init() {}

    func startChecking() {
        check()
        timer = Timer.scheduledTimer(withTimeInterval: checkInterval, repeats: true) { [weak self] _ in
            self?.check()
        }
    }

    func stopChecking() {
        timer?.invalidate()
        timer = nil
    }

    func dismiss() {
        isDismissed = true
        // Remember this version was dismissed
        if let v = availableVersion {
            UserDefaults.standard.set(v, forKey: "update.dismissed")
        }
    }

    func applyUpdate() {
        guard let url = downloadURL else {
            // Fallback: relaunch
            relaunch()
            return
        }

        #if os(macOS)
        NSWorkspace.shared.open(url)
        // Give the browser a moment, then quit so the installer can replace us
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            NSApplication.shared.terminate(nil)
        }
        #else
        UIApplication.shared.open(url)
        #endif
    }

    // MARK: - Private

    private func check() {
        Task {
            do {
                let (data, _) = try await URLSession.shared.data(from: manifestURL)
                let manifest = try JSONDecoder().decode(VersionManifest.self, from: data)

                await MainActor.run {
                    let current = currentVersion()
                    let dismissed = UserDefaults.standard.string(forKey: "update.dismissed")

                    if manifest.version != current && manifest.version != dismissed {
                        availableVersion = manifest.version
                        releaseNotes = manifest.notes
                        downloadURL = manifest.url.flatMap { URL(string: $0) }
                        isDismissed = false
                    }
                }
            } catch {
                // Silent fail — no network is fine
            }
        }
    }

    private func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private func relaunch() {
        #if os(macOS)
        let url = URL(fileURLWithPath: Bundle.main.resourcePath!)
        let path = url.deletingLastPathComponent().deletingLastPathComponent().absoluteString
        let task = Process()
        task.launchPath = "/usr/bin/open"
        task.arguments = ["-n", path]
        task.launch()
        NSApplication.shared.terminate(nil)
        #endif
    }
}

// MARK: - Manifest

private struct VersionManifest: Decodable {
    let version: String
    let notes: String?
    let url: String?
}
