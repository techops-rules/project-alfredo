import Foundation

/// Manages APNs device token registration and sends the token to the Pi bridge
/// so it can fire push notifications back to the iPhone.
@Observable
final class PushTokenService {
    static let shared = PushTokenService()

    private(set) var deviceToken: String?
    private(set) var isRegistered = false

    private init() {}

    /// Called from AppDelegate when APNs registration succeeds
    func register(token: String) {
        self.deviceToken = token
        sendTokenToBridge(token)
    }

    private func sendTokenToBridge(_ token: String) {
        let host = UserDefaults.standard.string(forKey: "terminal.piHost") ?? ""
        guard !host.isEmpty else { return }
        let port = UserDefaults.standard.object(forKey: "terminal.piPort") as? Int ?? 8420

        guard let url = URL(string: "http://\(host):\(port)/register-push") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: [
            "device_token": token,
            "bundle_id": Bundle.main.bundleIdentifier ?? "com.todd.alfredo",
        ])

        URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                DispatchQueue.main.async { self?.isRegistered = true }
            } else if let error = error {
                print("[APNs] Token registration failed: \(error.localizedDescription)")
            }
        }.resume()
    }
}
