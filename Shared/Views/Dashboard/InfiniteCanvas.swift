import SwiftUI

struct InfiniteCanvas<Content: View>: View {
    let worldSize: CGSize
    @Binding var offset: CGPoint
    @ViewBuilder let content: () -> Content

    @State private var dragStartOffset: CGPoint = .zero
    @State private var isBouncing = false

    // Physics constants
    private let rubberBandResistance: CGFloat = 0.35
    private let maxOverscroll: CGFloat = 120
    private let bounceSpring = Animation.spring(response: 0.45, dampingFraction: 0.7, blendDuration: 0.1)
    // Momentum spring — matches design brief spec
    private let momentumSpring = Animation.interactiveSpring(response: 0.6, dampingFraction: 0.78)

    var body: some View {
        GeometryReader { geo in
            let viewportSize = geo.size
            let edges = edgeBounds(viewportSize: viewportSize)

            ZStack(alignment: .topLeading) {
                content()
                    .frame(width: worldSize.width, height: worldSize.height, alignment: .topLeading)
                    .offset(x: offset.x, y: offset.y)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()
            .contentShape(Rectangle())
            #if os(macOS)
            // Scroll wheel must be captured BEFORE .drawingGroup() rasterizes
            // the content into a Metal texture (which absorbs scroll events).
            .onScrollWheel { deltaX, deltaY, phase in
                if phase == .ended || phase == .cancelled {
                    bounceBack(viewportSize: viewportSize)
                    return
                }

                if phase == .began {
                    isBouncing = false
                }

                let rawX = offset.x + deltaX
                let rawY = offset.y + deltaY

                offset.x = rubberBand(rawX, min: edges.minX, max: edges.maxX)
                offset.y = rubberBand(rawY, min: edges.minY, max: edges.maxY)
            }
            #endif
            // NOTE: .drawingGroup() removed — it rasterizes NSViewRepresentable
            // text fields (TerminalTextField) into a Metal texture, which captures
            // the macOS Secure Input overlay (yellow 🚫) on unsigned debug builds.
            #if os(iOS)
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        handleDragChanged(value, edges: edges)
                    }
                    .onEnded { value in
                        handleDragEnded(value, viewportSize: viewportSize)
                    }
            )
            #else
            .gesture(
                DragGesture(minimumDistance: 5)
                    .onChanged { value in
                        handleDragChanged(value, edges: edges)
                    }
                    .onEnded { value in
                        handleDragEnded(value, viewportSize: viewportSize)
                    }
            )
            #endif
        }
    }

    // MARK: - Drag Handling

    private func handleDragChanged(_ value: DragGesture.Value, edges: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)) {
        isBouncing = false

        if dragStartOffset == .zero {
            dragStartOffset = offset
        }

        let rawX = dragStartOffset.x + value.translation.width
        let rawY = dragStartOffset.y + value.translation.height

        // Direct assignment — no animation during active drag for zero-lag tracking
        offset.x = rubberBand(rawX, min: edges.minX, max: edges.maxX)
        offset.y = rubberBand(rawY, min: edges.minY, max: edges.maxY)
    }

    private func handleDragEnded(_ value: DragGesture.Value, viewportSize: CGSize) {
        let edges = edgeBounds(viewportSize: viewportSize)
        dragStartOffset = .zero

        // Use SwiftUI's animation system for momentum instead of Timer.
        // The spring runs on the render thread — buttery smooth, no RunLoop contention.
        let velocityScale: CGFloat = 0.15
        let targetX = offset.x + (value.velocity.width * velocityScale)
        let targetY = offset.y + (value.velocity.height * velocityScale)

        // Clamp target to world edges
        let clampedX = clamp(targetX, min: edges.minX, max: edges.maxX)
        let clampedY = clamp(targetY, min: edges.minY, max: edges.maxY)

        withAnimation(momentumSpring) {
            offset.x = clampedX
            offset.y = clampedY
        }
    }

    // MARK: - Edge Bounds

    private func edgeBounds(viewportSize: CGSize) -> (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat) {
        let minX = min(0, -(worldSize.width - viewportSize.width))
        let minY = min(0, -(worldSize.height - viewportSize.height))
        return (minX, 0, minY, 0)
    }

    // MARK: - Rubber Band

    private func rubberBand(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        if value < minVal {
            let overscroll = minVal - value
            let dampened = maxOverscroll * (1 - exp(-overscroll / maxOverscroll * rubberBandResistance))
            return minVal - dampened
        } else if value > maxVal {
            let overscroll = value - maxVal
            let dampened = maxOverscroll * (1 - exp(-overscroll / maxOverscroll * rubberBandResistance))
            return maxVal + dampened
        }
        return value
    }

    // MARK: - Bounce Back

    private func bounceBack(viewportSize: CGSize) {
        let edges = edgeBounds(viewportSize: viewportSize)
        guard isOverscrolled(edges: edges) else { return }

        isBouncing = true
        withAnimation(bounceSpring) {
            offset.x = clamp(offset.x, min: edges.minX, max: edges.maxX)
            offset.y = clamp(offset.y, min: edges.minY, max: edges.maxY)
        }
    }

    private func isOverscrolled(edges: (minX: CGFloat, maxX: CGFloat, minY: CGFloat, maxY: CGFloat)) -> Bool {
        offset.x < edges.minX || offset.x > edges.maxX ||
        offset.y < edges.minY || offset.y > edges.maxY
    }

    private func clamp(_ value: CGFloat, min minVal: CGFloat, max maxVal: CGFloat) -> CGFloat {
        Swift.min(Swift.max(value, minVal), maxVal)
    }
}

// MARK: - macOS Scroll Wheel

#if os(macOS)
struct ScrollWheelModifier: ViewModifier {
    let onScroll: (CGFloat, CGFloat, NSEvent.Phase) -> Void

    func body(content: Content) -> some View {
        content.background(
            ScrollWheelView(onScroll: onScroll)
        )
    }
}

struct ScrollWheelView: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, NSEvent.Phase) -> Void

    func makeNSView(context: Context) -> ScrollWheelNSView {
        let view = ScrollWheelNSView()
        view.onScroll = onScroll
        return view
    }

    func updateNSView(_ nsView: ScrollWheelNSView, context: Context) {
        nsView.onScroll = onScroll
    }
}

class ScrollWheelNSView: NSView {
    var onScroll: ((CGFloat, CGFloat, NSEvent.Phase) -> Void)?

    override func scrollWheel(with event: NSEvent) {
        let phase: NSEvent.Phase
        if event.momentumPhase != [] {
            phase = event.momentumPhase
        } else {
            phase = event.phase
        }
        onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, phase)
    }

    // Pass through all non-scroll events so clicks/drags reach SwiftUI
    override func mouseDown(with event: NSEvent) { super.mouseDown(with: event) }
    override func mouseUp(with event: NSEvent) { super.mouseUp(with: event) }
    override func mouseDragged(with event: NSEvent) { super.mouseDragged(with: event) }
    override var acceptsFirstResponder: Bool { false }
}

extension View {
    func onScrollWheel(perform: @escaping (CGFloat, CGFloat, NSEvent.Phase) -> Void) -> some View {
        modifier(ScrollWheelModifier(onScroll: perform))
    }
}
#endif
