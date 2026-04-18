import SwiftUI
import Combine

/// Persisted collapsed/expanded state per widget. When collapsed, the widget
/// renders header-only and the iOS flow layout reclaims the freed space so
/// neighbors reflow up.
@MainActor
final class WidgetCollapseService: ObservableObject {
    static let shared = WidgetCollapseService()

    @Published private(set) var collapsed: Set<String> = []

    /// Header-only height (in points) when a widget is collapsed.
    static let collapsedHeight: CGFloat = 32

    private let key = "widget.collapsed.ids"

    private init() {
        if let stored = UserDefaults.standard.array(forKey: key) as? [String] {
            collapsed = Set(stored)
        }
    }

    func isCollapsed(_ id: String) -> Bool {
        collapsed.contains(id)
    }

    func toggle(_ id: String) {
        if collapsed.contains(id) {
            collapsed.remove(id)
        } else {
            collapsed.insert(id)
        }
        save()
    }

    private func save() {
        UserDefaults.standard.set(Array(collapsed), forKey: key)
    }
}
