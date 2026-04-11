import SwiftUI

// Wraps a widget with interactive move/resize handles
struct DraggableWidgetContainer<Content: View>: View {
    let widgetId: String
    @ObservedObject var layoutManager: WidgetLayoutManager
    let defaultLayout: WidgetLayoutState
    var isEditMode: Bool = true
    @ViewBuilder let content: () -> Content

    @State private var dragStartPos: CGPoint = .zero
    @State private var isDragging = false
    @State private var resizeStartSize: CGSize = .zero
    @State private var isResizing = false
    @State private var isHovering = false

    private let minWidth: CGFloat = 180
    private let minHeight: CGFloat = 100

    private var layout: WidgetLayoutState {
        layoutManager.getLayout(widgetId, default: defaultLayout)
    }

    private var showHandles: Bool {
        #if os(macOS)
        return isEditMode && (isHovering || isDragging || isResizing)
        #else
        return isEditMode
        #endif
    }

    var body: some View {
        let layout = self.layout
        ZStack(alignment: .topLeading) {
            content()
                .frame(width: layout.size.width, height: layout.size.height)
                .gesture(
                    isEditMode ?
                    DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            if !isDragging {
                                dragStartPos = layout.position
                                isDragging = true
                            }
                            let newPos = CGPoint(
                                x: dragStartPos.x + value.translation.width,
                                y: dragStartPos.y + value.translation.height
                            )
                            layoutManager.setPositionLive(widgetId, to: newPos)
                        }
                        .onEnded { value in
                            let finalPos = CGPoint(
                                x: dragStartPos.x + value.translation.width,
                                y: dragStartPos.y + value.translation.height
                            )
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                                layoutManager.setPositionFinal(widgetId, to: finalPos)
                            }
                            isDragging = false
                            dragStartPos = .zero
                        }
                    : nil
                )

            // Resize handle (bottom-right corner)
            if showHandles {
                resizeHandle
                    .position(
                        x: layout.size.width - 12,
                        y: layout.size.height - 12
                    )
                    .gesture(
                        DragGesture(minimumDistance: 3)
                            .onChanged { value in
                                if !isResizing {
                                    resizeStartSize = layout.size
                                    isResizing = true
                                }
                                let newSize = CGSize(
                                    width: max(minWidth, resizeStartSize.width + value.translation.width),
                                    height: max(minHeight, resizeStartSize.height + value.translation.height)
                                )
                                layoutManager.setSizeLive(widgetId, to: newSize)
                            }
                            .onEnded { value in
                                let finalSize = CGSize(
                                    width: max(minWidth, resizeStartSize.width + value.translation.width),
                                    height: max(minHeight, resizeStartSize.height + value.translation.height)
                                )
                                withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.8)) {
                                    layoutManager.setSizeFinal(widgetId, to: finalSize)
                                }
                                isResizing = false
                                resizeStartSize = .zero
                            }
                    )
            }

            // Edit mode highlight ring
            if showHandles {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(0.3), lineWidth: 1)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .allowsHitTesting(false)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .position(x: layout.position.x + layout.size.width / 2, y: layout.position.y + layout.size.height / 2)
        .zIndex(isDragging || isResizing ? 1000 : 0)
        #if os(macOS)
        .onHover { hovering in
            isHovering = hovering
        }
        #endif
    }

    // MARK: - Resize Handle

    @ViewBuilder
    private var resizeHandle: some View {
        ZStack {
            Color.clear
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())

            Path { path in
                path.move(to: CGPoint(x: 4, y: 12))
                path.addLine(to: CGPoint(x: 12, y: 4))
                path.move(to: CGPoint(x: 8, y: 12))
                path.addLine(to: CGPoint(x: 12, y: 8))
            }
            .stroke(Color.accentColor.opacity(0.6), lineWidth: 1.5)
            .frame(width: 16, height: 16)
        }
        #if os(macOS)
        .onHover { hovering in
            if hovering {
                NSCursor.crosshair.push()
            } else {
                NSCursor.pop()
            }
        }
        #endif
    }
}
