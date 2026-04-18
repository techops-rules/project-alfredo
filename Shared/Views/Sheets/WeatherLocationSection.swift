import SwiftUI

struct WeatherLocationSection: View {
    @Environment(\.theme) private var theme
    @StateObject private var prefs = LocationPreferences.shared
    @State private var query: String = ""
    @State private var currentLabel: String = WeatherService.shared.locationLabel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "location.fill")
                    .foregroundColor(theme.accentFull)
                Text(currentLabel.uppercased())
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(ThemeManager.textPrimary)
                Spacer()
                if prefs.isResolving {
                    ProgressView().scaleEffect(0.7)
                }
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .background(ThemeManager.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            HStack(spacing: 8) {
                TextField("zip, city, or city, state", text: $query)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(ThemeManager.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(theme.accentBorder, lineWidth: 1)
                    )
                    #if os(iOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.default)
                    .submitLabel(.go)
                    #endif
                    .onSubmit { submit() }

                Button("SET", action: submit)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(ThemeManager.surface)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(theme.accentFull)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .disabled(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.plain)
            }

            Button {
                prefs.useCurrentLocation()
                pollLabel()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "location.viewfinder")
                    Text("USE CURRENT LOCATION")
                        .tracking(1.4)
                }
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(theme.accentFull)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(theme.accentFull.opacity(0.5), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)

            if let err = prefs.lastError {
                Text(err)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(.red.opacity(0.85))
            }
        }
    }

    private func submit() {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return }
        Task {
            await prefs.setLocation(from: q)
            query = ""
            pollLabel()
        }
    }

    /// Poll for label update after async resolve.
    private func pollLabel() {
        Task { @MainActor in
            for _ in 0..<20 {
                let label = WeatherService.shared.locationLabel
                if label != currentLabel {
                    currentLabel = label
                    return
                }
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }
    }
}
