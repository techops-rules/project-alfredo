import SwiftUI

/// Tracks the intrinsic content height of each widget so the iOS flow layout
/// can shrink slot heights down to what the widget actually needs (no empty
/// space below short content). Heights are measured at runtime via a
/// PreferenceKey emitted from `WidgetShell`.
@MainActor
final class WidgetMeasurementService: ObservableObject {
    static let shared = WidgetMeasurementService()

    @Published private(set) var intrinsicHeights: [String: CGFloat] = [:]

    private init() {}

    func report(_ id: String, height: CGFloat) {
        let rounded = ceil(height)
        guard intrinsicHeights[id] != rounded else { return }
        intrinsicHeights[id] = rounded
    }

    func intrinsicHeight(_ id: String) -> CGFloat? {
        intrinsicHeights[id]
    }
}

/// Preference key for bubbling a widget's measured content height up to its
/// container. Keyed by widgetId since multiple widgets may sit in the same
/// preference scope.
struct WidgetIntrinsicHeightKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: max)
    }
}

private struct WidgetCollapseIdKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    /// The widget's stable ID, plumbed from `DraggableWidgetContainer` down
    /// into `WidgetShell` so collapse state and measurement reports key
    /// correctly without each widget having to re-thread the id manually.
    var widgetCollapseId: String? {
        get { self[WidgetCollapseIdKey.self] }
        set { self[WidgetCollapseIdKey.self] = newValue }
    }
}
