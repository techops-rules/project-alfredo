import SwiftUI
import AppKit

@Observable
final class MenuBarManager: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?

    func setup() {
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "alfredo")
        statusItem.button?.action = #selector(togglePopover)
        statusItem.button?.target = self
        self.statusItem = statusItem

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 320, height: 360)
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(rootView: MenuBarContent())
        self.popover = popover
    }

    @objc private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    func closePopover() {
        popover?.performClose(nil)
    }
}

struct MenuBarContent: View {
    @State private var scratchpadService = ScratchpadService()
    @State private var taskBoard = TaskBoardService()
    @State private var whatNext = WhatNextEngine()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Quick capture
            QuickCaptureField(placeholder: "quick capture...", onSubmit: { line in
                scratchpadService.addLine(line)
            })

            Divider().background(ThemeManager.textSecondary.opacity(0.2))

            // Next events (Phase 1: static)
            VStack(alignment: .leading, spacing: 6) {
                Text("UPCOMING")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundColor(ThemeManager.textSecondary)
                    .tracking(1)

                ForEach(CalendarEvent.sampleEvents.prefix(3)) { event in
                    HStack {
                        Text(event.timeString)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundColor(AccentColor.ice.color)
                        Text(event.title)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundColor(ThemeManager.textPrimary)
                            .lineLimit(1)
                    }
                }
            }

            Divider().background(ThemeManager.textSecondary.opacity(0.2))

            // Task count
            Text("\(taskBoard.todayDoneCount)/\(taskBoard.todayTotalCount) tasks done")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(ThemeManager.textPrimary)

            // What Next suggestion
            if let next = whatNext.suggestNext(from: taskBoard.todayTasks) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9))
                        .foregroundColor(AccentColor.ice.color)
                    Text(next.displayText)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(ThemeManager.textPrimary)
                        .lineLimit(1)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(ThemeManager.background)
    }
}
