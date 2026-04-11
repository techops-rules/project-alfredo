import SwiftUI

struct EventBriefingSheet: View {
    let event: CalendarEvent
    @Environment(\.theme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var briefing: MeetingBriefing?
    @State private var isLoading = true

    private let prepService = MeetingPrepService.shared

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
            Divider().background(ThemeManager.textSecondary.opacity(0.2))

            if isLoading {
                loadingView
            } else if let briefing = briefing {
                briefingContent(briefing)
            }
        }
        .background(ThemeManager.background)
        .task {
            // Check cache first (pre-loaded)
            if let cached = prepService.cachedBriefing(for: event.id) {
                briefing = cached
                isLoading = false
            } else {
                briefing = await prepService.prepareBriefing(for: event)
                isLoading = false
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("MEETING BRIEF")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .tracking(2)

                Text(event.title)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)

                HStack(spacing: 8) {
                    Text(event.timeString)
                    if let loc = event.location {
                        Text("·")
                        Text(loc)
                    }
                    if let attendees = event.attendeeNames {
                        Text("·")
                        Text("\(attendees.count) people")
                    }
                }
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
            }

            Spacer()

            if let briefing = briefing {
                ConfidenceBadge(score: briefing.overallConfidence)
            }
        }
        .padding(16)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .tint(theme.accentFull)
            Text("gathering context...")
                .font(.system(size: 10, design: .monospaced))
                .foregroundColor(ThemeManager.textSecondary)
            Spacer()
        }
    }

    // MARK: - Briefing Content

    private func briefingContent(_ briefing: MeetingBriefing) -> some View {
        VStack(spacing: 0) {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Attendees
                if let names = event.attendeeNames, !names.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ATTENDEES")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1.5)
                        Text(names.joined(separator: ", "))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(ThemeManager.textPrimary)
                    }
                }

                // Summary
                if !briefing.summary.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("SUMMARY")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1.5)
                        Text(briefing.summary)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ThemeManager.textPrimary)
                    }
                }

                // Context sources
                if !briefing.contextSources.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("CONTEXT SOURCES")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary)
                            .tracking(1.5)

                        ForEach(briefing.contextSources) { source in
                            ContextSourceRow(source: source)
                        }
                    }
                }

                // Low confidence warning
                if briefing.overallConfidence < 0.4 {
                    Text("Low confidence -- limited context found. Check sources manually.")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(ThemeManager.warning)
                        .padding(8)
                        .background(ThemeManager.warning.opacity(0.1))
                        .cornerRadius(4)
                }

                Spacer(minLength: 8)
            }
            .padding(16)
        }

        // Action buttons
        HStack(spacing: 12) {
            if let url = event.meetingURL {
                Button {
                    #if os(iOS)
                    UIApplication.shared.open(url)
                    #elseif os(macOS)
                    NSWorkspace.shared.open(url)
                    #endif
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "video")
                        Text("Join Meeting")
                    }
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(theme.accentFull)
                    .foregroundColor(.black)
                    .cornerRadius(6)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            Button {
                dismiss()
            } label: {
                Text("Dismiss")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.plain)
        }
        .padding(16)
        } // VStack
    }
}

// MARK: - Confidence Badge

struct ConfidenceBadge: View {
    let score: Double

    private var color: Color {
        if score >= 0.8 { return Color(red: 0.596, green: 0.765, blue: 0.475) } // #98C379
        if score >= 0.5 { return Color(red: 0.898, green: 0.753, blue: 0.482) } // #E5C07B
        return Color(red: 0.878, green: 0.424, blue: 0.459) } // #E06C75

    var body: some View {
        Text(String(format: "[%.2f]", score))
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundColor(color)
    }
}

// MARK: - Context Source Row

struct ContextSourceRow: View {
    let source: ContextSource
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ConfidenceBadge(score: source.confidence)
                .frame(width: 44, alignment: .leading)

            VStack(alignment: .leading, spacing: 2) {
                Text(source.title)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                Text(source.snippet)
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .lineLimit(2)
            }

            Spacer()

            if source.url != nil {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9))
                    .foregroundColor(ThemeManager.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}
