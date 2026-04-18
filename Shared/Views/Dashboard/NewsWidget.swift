import SwiftUI

struct NewsWidget: View {
    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics
    @State private var news = NewsService.shared
    @State private var selected: NewsHeadline?

    var body: some View {
        WidgetShell(title: "TOP.STORIES", zone: "feed") {
            VStack(alignment: .leading, spacing: metrics.rowSpacing) {
                let trio = news.currentTrio
                if trio.isEmpty {
                    Text("fetching headlines…")
                        .font(.system(size: metrics.captionFontSize, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary.opacity(0.7))
                        .padding(.vertical, 8)
                } else {
                    ForEach(trio) { item in
                        NewsRow(item: item)
                            .contentShape(Rectangle())
                            .onTapGesture { selected = item }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .task {
            news.start()
        }
        .sheet(item: $selected) { item in
            NewsStorySheet(item: item)
        }
    }
}

private struct NewsRow: View {
    let item: NewsHeadline
    @Environment(\.theme) private var theme
    @Environment(\.widgetMetrics) private var metrics

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(item.source)
                    .font(.system(size: metrics.badgeFontSize, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundColor(theme.accentFull)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(theme.accentBadge)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                if let published = item.published {
                    Text(published.relativeShort)
                        .font(.system(size: metrics.captionFontSize - 1, design: .monospaced))
                        .foregroundColor(ThemeManager.textSecondary.opacity(0.6))
                }
                Spacer(minLength: 0)
            }
            Text(item.title)
                .font(.system(size: metrics.bodyFontSize, design: .monospaced))
                .foregroundColor(ThemeManager.textPrimary)
                .lineLimit(metrics.isCompact ? 2 : 3)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
        .padding(.vertical, 3)
    }
}

private extension Date {
    var relativeShort: String {
        let delta = Date().timeIntervalSince(self)
        if delta < 60 { return "just now" }
        if delta < 3600 { return "\(Int(delta / 60))m ago" }
        if delta < 86400 { return "\(Int(delta / 3600))h ago" }
        return "\(Int(delta / 86400))d ago"
    }
}
