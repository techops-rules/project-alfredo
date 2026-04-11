import SwiftUI

enum WidgetSizeClass: String {
    case compact
    case regular
    case expanded

    static func classify(size: CGSize) -> WidgetSizeClass {
        let width = size.width
        let height = size.height
        let minSide = min(width, height)

        if width < 260 || height < 170 || minSide < 170 {
            return .compact
        }
        if width >= 430 && height >= 240 {
            return .expanded
        }
        return .regular
    }
}

struct WidgetContentMetrics {
    let sizeClass: WidgetSizeClass
    let containerSize: CGSize
    let contentPadding: CGFloat
    let rowSpacing: CGFloat
    let sectionSpacing: CGFloat
    let headerVerticalPadding: CGFloat
    let titleFontSize: CGFloat
    let bodyFontSize: CGFloat
    let captionFontSize: CGFloat
    let emphasisFontSize: CGFloat
    let badgeFontSize: CGFloat
    let primaryListLimit: Int
    let secondaryListLimit: Int
    let hourWindow: Int
    let gridColumns: Int

    init(sizeClass: WidgetSizeClass, containerSize: CGSize, theme: ThemeManager) {
        self.sizeClass = sizeClass
        self.containerSize = containerSize

        switch sizeClass {
        case .compact:
            contentPadding = 8
            rowSpacing = 6
            sectionSpacing = 8
            headerVerticalPadding = 6
            titleFontSize = max(9, theme.fontSize - 2)
            bodyFontSize = max(10, theme.fontSize - 1)
            captionFontSize = max(8, theme.fontSize - 4)
            emphasisFontSize = max(14, theme.fontSize + 2)
            badgeFontSize = max(8, theme.fontSize - 4)
            primaryListLimit = 3
            secondaryListLimit = 2
            hourWindow = 5
            gridColumns = 2
        case .regular:
            contentPadding = 12
            rowSpacing = 8
            sectionSpacing = 12
            headerVerticalPadding = 8
            titleFontSize = theme.fontSize
            bodyFontSize = theme.fontSize
            captionFontSize = max(8, theme.fontSize - 3)
            emphasisFontSize = max(18, theme.fontSize + 5)
            badgeFontSize = max(9, theme.fontSize - 2)
            primaryListLimit = 5
            secondaryListLimit = 4
            hourWindow = 7
            gridColumns = 3
        case .expanded:
            contentPadding = 14
            rowSpacing = 10
            sectionSpacing = 14
            headerVerticalPadding = 9
            titleFontSize = theme.fontSize + 1
            bodyFontSize = theme.fontSize
            captionFontSize = max(9, theme.fontSize - 2)
            emphasisFontSize = max(20, theme.fontSize + 7)
            badgeFontSize = max(10, theme.fontSize - 1)
            primaryListLimit = 8
            secondaryListLimit = 6
            hourWindow = 11
            gridColumns = 3
        }
    }

    var isCompact: Bool { sizeClass == .compact }
    var isExpanded: Bool { sizeClass == .expanded }
    var prefersStackedStats: Bool { sizeClass == .compact && containerSize.width < 320 }
}

private struct WidgetSizeClassKey: EnvironmentKey {
    static let defaultValue: WidgetSizeClass = .regular
}

private struct WidgetContentMetricsKey: EnvironmentKey {
    static let defaultValue = WidgetContentMetrics(
        sizeClass: .regular,
        containerSize: CGSize(width: 320, height: 220),
        theme: ThemeManager.shared
    )
}

extension EnvironmentValues {
    var widgetSizeClass: WidgetSizeClass {
        get { self[WidgetSizeClassKey.self] }
        set { self[WidgetSizeClassKey.self] = newValue }
    }

    var widgetMetrics: WidgetContentMetrics {
        get { self[WidgetContentMetricsKey.self] }
        set { self[WidgetContentMetricsKey.self] = newValue }
    }
}

struct WidgetShell<Content: View>: View {
    let title: String
    var badge: String? = nil
    var badgeView: AnyView? = nil
    var zone: String? = nil
    @ViewBuilder let content: () -> Content

    @Environment(\.theme) private var theme
    @State private var isCollapsed = false

    var body: some View {
        GeometryReader { geo in
            let metrics = WidgetContentMetrics(
                sizeClass: WidgetSizeClass.classify(size: geo.size),
                containerSize: geo.size,
                theme: theme
            )

            VStack(spacing: 0) {
                Button(action: {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        isCollapsed.toggle()
                    }
                }) {
                    HStack(spacing: metrics.isCompact ? 6 : 8) {
                        Image(systemName: isCollapsed ? "chevron.right" : "chevron.down")
                            .font(.system(size: metrics.captionFontSize + 1, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.accentFull)
                            .frame(width: metrics.isCompact ? 10 : 12)

                        Text(title)
                            .font(.system(size: metrics.titleFontSize, weight: .bold, design: .monospaced))
                            .foregroundColor(theme.accentFull)
                            .tracking(metrics.isCompact ? 1 : 2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .layoutPriority(1)

                        if let badgeView {
                            badgeView
                                .padding(.horizontal, metrics.isCompact ? 6 : 8)
                                .padding(.vertical, 2)
                                .fixedSize()
                        } else if let badge {
                            Text(badge)
                                .font(.system(size: metrics.badgeFontSize, design: .monospaced))
                                .foregroundColor(theme.accentFull)
                                .padding(.horizontal, metrics.isCompact ? 6 : 8)
                                .padding(.vertical, 2)
                                .background(theme.accentBadge)
                                .clipShape(RoundedRectangle(cornerRadius: 4))
                        }

                        Spacer(minLength: 0)

                        if let zone {
                            Text(zone)
                                .font(.system(size: metrics.captionFontSize, design: .monospaced))
                                .foregroundColor(ThemeManager.textSecondary.opacity(0.5))
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                        }
                    }
                    .padding(.horizontal, metrics.isCompact ? 10 : 12)
                    .padding(.vertical, metrics.headerVerticalPadding)
                    .background(theme.accentHeaderBg)
                }
                .buttonStyle(.plain)

                if !isCollapsed {
                    content()
                        .environment(\.widgetSizeClass, metrics.sizeClass)
                        .environment(\.widgetMetrics, metrics)
                        .padding(metrics.contentPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
            .background(.ultraThinMaterial.opacity(0.3))
            .background(ThemeManager.surface)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(theme.accentBorder, style: StrokeStyle(
                        lineWidth: theme.borderWidth,
                        dash: theme.borderStrokeDash
                    ))
            )
            .overlay(
                AsciiBorderOverlay(chars: theme.borderChars, color: theme.accentBorder)
            )
        }
    }
}

// MARK: - ASCII Border Overlay

struct AsciiBorderOverlay: View {
    let chars: BorderChars
    let color: Color

    private let charSize: CGFloat = 10

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height

            cornerChar(chars.tl)
                .position(x: charSize / 2, y: charSize / 2)
            cornerChar(chars.tr)
                .position(x: w - charSize / 2, y: charSize / 2)
            cornerChar(chars.bl)
                .position(x: charSize / 2, y: h - charSize / 2)
            cornerChar(chars.br)
                .position(x: w - charSize / 2, y: h - charSize / 2)

            let hCount = max(0, Int((w - charSize * 3) / (charSize * 1.2)))
            if hCount > 0 {
                let spacing = (w - charSize * 2) / CGFloat(hCount + 1)
                ForEach(0..<hCount, id: \.self) { i in
                    edgeChar(chars.h)
                        .position(x: charSize + spacing * CGFloat(i + 1), y: charSize / 2 - 1)
                }
                ForEach(0..<hCount, id: \.self) { i in
                    edgeChar(chars.h)
                        .position(x: charSize + spacing * CGFloat(i + 1), y: h - charSize / 2 + 1)
                }
            }

            let vCount = max(0, Int((h - charSize * 3) / (charSize * 1.5)))
            if vCount > 0 {
                let spacing = (h - charSize * 2) / CGFloat(vCount + 1)
                ForEach(0..<vCount, id: \.self) { i in
                    edgeChar(chars.v)
                        .position(x: charSize / 2 - 1, y: charSize + spacing * CGFloat(i + 1))
                }
                ForEach(0..<vCount, id: \.self) { i in
                    edgeChar(chars.v)
                        .position(x: w - charSize / 2 + 1, y: charSize + spacing * CGFloat(i + 1))
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func cornerChar(_ ch: String) -> some View {
        Text(ch)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundColor(color.opacity(0.7))
    }

    private func edgeChar(_ ch: String) -> some View {
        Text(ch)
            .font(.system(size: 9, design: .monospaced))
            .foregroundColor(color.opacity(0.35))
    }
}
