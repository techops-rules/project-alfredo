import SwiftUI

// Stores layout state for a single widget
struct WidgetLayoutState: Codable, Equatable {
    var position: CGPoint
    var size: CGSize

    init(position: CGPoint, size: CGSize) {
        self.position = position
        self.size = size
    }
}

// Manages all widget positions and sizes
class WidgetLayoutManager: ObservableObject {
    @Published var layouts: [String: WidgetLayoutState] = [:]
    private let gridSize: CGFloat = 20
    private let snapThreshold: CGFloat = 8
    private var saveTask: DispatchWorkItem?

    init() {
        loadLayouts()
    }

    func getLayout(_ widgetId: String, default defaultLayout: WidgetLayoutState) -> WidgetLayoutState {
        if let existing = layouts[widgetId] {
            return existing
        }
        layouts[widgetId] = defaultLayout
        return defaultLayout
    }

    // Live position update during drag — no snap, no save
    func setPositionLive(_ widgetId: String, to position: CGPoint) {
        guard var layout = layouts[widgetId] else { return }
        layout.position = position
        layouts[widgetId] = layout
    }

    // Final position on drag end — snap + save
    func setPositionFinal(_ widgetId: String, to position: CGPoint) {
        guard var layout = layouts[widgetId] else { return }
        layout.position = snapPoint(position)
        layouts[widgetId] = layout
        debounceSave()
    }

    // Live size update during resize — no snap, no save
    func setSizeLive(_ widgetId: String, to size: CGSize) {
        guard var layout = layouts[widgetId] else { return }
        layout.size = CGSize(
            width: max(200, size.width),
            height: max(100, size.height)
        )
        layouts[widgetId] = layout
    }

    // Final size on resize end — snap + save
    func setSizeFinal(_ widgetId: String, to size: CGSize) {
        guard var layout = layouts[widgetId] else { return }
        layout.size = CGSize(
            width: snap(max(200, size.width)),
            height: snap(max(100, size.height))
        )
        layouts[widgetId] = layout
        debounceSave()
    }

    // MARK: - Snap

    private func snap(_ value: CGFloat) -> CGFloat {
        let nearest = (value / gridSize).rounded() * gridSize
        if abs(value - nearest) < snapThreshold {
            return nearest
        }
        return value
    }

    private func snapPoint(_ point: CGPoint) -> CGPoint {
        CGPoint(x: snap(point.x), y: snap(point.y))
    }

    // MARK: - Persistence

    private func debounceSave() {
        saveTask?.cancel()
        let task = DispatchWorkItem { [weak self] in
            self?.saveLayouts()
        }
        saveTask = task
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: task)
    }

    private func saveLayouts() {
        let icloud = iCloudService.shared
        if let encoded = try? JSONEncoder().encode(layouts) {
            icloud.writeFileData(encoded, to: icloud.layoutURL)
        }
    }

    private func loadLayouts() {
        let icloud = iCloudService.shared
        if let data = icloud.readFileData(at: icloud.layoutURL),
           let decoded = try? JSONDecoder().decode([String: WidgetLayoutState].self, from: data) {
            layouts = decoded
        }
    }

    func reset() {
        layouts.removeAll()
        saveLayouts()
    }
}
