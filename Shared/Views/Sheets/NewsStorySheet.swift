import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct NewsStorySheet: View {
    let item: NewsHeadline
    @Environment(\.dismiss) private var dismiss
    @Environment(\.theme) private var theme
    @State private var readingList = ReadingListService.shared

    @State private var claudeState: AskState = .idle
    @State private var claudeText: String = ""

    enum AskState { case idle, loading, loaded, error }

    var body: some View {
        ZStack {
            ThemeManager.surface.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header
                    summaryBlock
                    Divider().background(theme.accentFull.opacity(0.25))
                    actionsBlock
                    if claudeState != .idle {
                        claudeBlock
                    }
                }
                .padding(18)
            }
        }
        .overlay(alignment: .topTrailing) {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .padding(14)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(item.source)
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundColor(theme.accentFull)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(theme.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                if let d = item.published {
                    Text(Self.datelineFormatter.string(from: d).uppercased())
                        .font(.system(size: 10, design: .monospaced))
                        .tracking(0.8)
                        .foregroundColor(ThemeManager.textSecondary)
                }
                Spacer()
            }
            Text(item.title)
                .font(.system(size: 20, weight: .semibold, design: .monospaced))
                .foregroundColor(ThemeManager.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var summaryBlock: some View {
        Group {
            if item.summary.isEmpty {
                Text("no summary in the feed. tap the link to read it at the source.")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary.opacity(0.7))
                    .italic()
            } else {
                Text(item.summary)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            ActionButton(label: "OPEN AT SOURCE", icon: "arrow.up.right.square", tint: theme.accentFull) {
                openExternal(item.url)
            }
            ActionButton(label: "GOOGLE IT", icon: "magnifyingglass", tint: ThemeManager.textPrimary) {
                if let url = googleURL { openExternal(url) }
            }
            ActionButton(label: claudeState == .loading ? "ASKING…" : "ASK CLAUDE",
                         icon: "sparkles",
                         tint: Color(red: 0.78, green: 0.60, blue: 0.90)) {
                askClaude()
            }
            .disabled(claudeState == .loading)

            let saved = readingList.contains(item)
            ActionButton(label: saved ? "SAVED · REMOVE" : "SAVE FOR LATER",
                         icon: saved ? "bookmark.fill" : "bookmark",
                         tint: saved ? Color(red: 1, green: 0.72, blue: 0.30) : ThemeManager.textSecondary) {
                readingList.toggle(item)
            }
        }
    }

    private var claudeBlock: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "sparkles")
                Text("CLAUDE")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.2)
            }
            .foregroundColor(Color(red: 0.78, green: 0.60, blue: 0.90))

            if claudeState == .loading {
                Text("thinking…")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .italic()
            } else if claudeState == .error {
                Text(claudeText)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundColor(.red.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(claudeText)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .background(ThemeManager.surface.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 4)
                .stroke(Color(red: 0.78, green: 0.60, blue: 0.90).opacity(0.35), lineWidth: 1)
        )
    }

    // MARK: - Actions

    private var googleURL: URL? {
        let q = item.title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "https://www.google.com/search?q=\(q)")
    }

    private func askClaude() {
        claudeState = .loading
        claudeText = ""
        let prompt = """
        Give me a tight, fact-checked briefing on this news story. In plain markdown:

        1. **Summary** — 2-3 sentences on what happened.
        2. **Fact check / context** — one sentence. Flag any single-source claims.
        3. **Sources** — a short bullet list of 3-5 additional outlets likely covering this (name + why).
        4. **Where to go deeper** — 2-3 links or search queries.

        No hedging, no preamble. If you don't know, say so.

        HEADLINE: \(item.title)
        SOURCE: \(item.source)
        URL: \(item.url.absoluteString)
        FEED SUMMARY: \(item.summary.isEmpty ? "(none)" : item.summary)
        """
        Task {
            do {
                let reply = try await ClaudeBridgeClient.ask(prompt: prompt, timeout: 45)
                await MainActor.run {
                    claudeText = reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    claudeState = .loaded
                }
            } catch {
                await MainActor.run {
                    claudeText = "bridge unreachable (\(error.localizedDescription)). check terminal.piHost / piPort."
                    claudeState = .error
                }
            }
        }
    }

    private func openExternal(_ url: URL) {
        #if canImport(UIKit)
        UIApplication.shared.open(url)
        #elseif canImport(AppKit)
        NSWorkspace.shared.open(url)
        #endif
    }

    private static let datelineFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MMM d, h:mm a"
        return f
    }()
}

private struct ActionButton: View {
    let label: String
    let icon: String
    let tint: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                Text(label)
                    .tracking(1.2)
                Spacer()
            }
            .font(.system(size: 11, weight: .bold, design: .monospaced))
            .foregroundColor(tint)
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .stroke(tint.opacity(0.45), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

#if canImport(AppKit)
import AppKit
#endif
