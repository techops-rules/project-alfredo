import SwiftUI

/// A text field that fully disables autocorrect, spell-check, and the macOS
/// suggestion bar. Both NSTextField and NSTextView still trigger the yellow
/// macOS suggestion overlay — this bypasses the Cocoa text system entirely
/// by handling keyDown directly in a custom NSView.

#if os(macOS)

/// Custom NSView that acts as a single-line text input by handling keyDown
/// events directly. Does NOT use NSTextInputClient or any Cocoa text system,
/// so macOS has nothing to attach its suggestion bar to.
class RawInputView: NSView {
    var text: String = "" { didSet { needsDisplay = true } }
    var placeholder: String = ""
    var font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    var textColor: NSColor = .white
    var cursorVisible = true
    var onTextChange: ((String) -> Void)?
    var onSubmit: (() -> Void)?

    private var cursorTimer: Timer?
    private var cursorIndex: Int = 0

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        wantsLayer = true
    }

    override func becomeFirstResponder() -> Bool {
        let result = super.becomeFirstResponder()
        if result {
            startCursorBlink()
        }
        return result
    }

    override func resignFirstResponder() -> Bool {
        let result = super.resignFirstResponder()
        stopCursorBlink()
        cursorVisible = false
        needsDisplay = true
        return result
    }

    private func startCursorBlink() {
        cursorVisible = true
        cursorTimer?.invalidate()
        cursorTimer = Timer.scheduledTimer(withTimeInterval: 0.53, repeats: true) { [weak self] _ in
            self?.cursorVisible.toggle()
            self?.needsDisplay = true
        }
    }

    private func stopCursorBlink() {
        cursorTimer?.invalidate()
        cursorTimer = nil
    }

    override func keyDown(with event: NSEvent) {
        guard let chars = event.charactersIgnoringModifiers else { return }
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        // Return → submit
        if event.keyCode == 36 {
            onSubmit?()
            return
        }

        // Backspace
        if event.keyCode == 51 {
            if !text.isEmpty && cursorIndex > 0 {
                let idx = text.index(text.startIndex, offsetBy: cursorIndex - 1)
                text.remove(at: idx)
                cursorIndex -= 1
                onTextChange?(text)
            }
            resetCursorBlink()
            return
        }

        // Forward delete
        if event.keyCode == 117 {
            if cursorIndex < text.count {
                let idx = text.index(text.startIndex, offsetBy: cursorIndex)
                text.remove(at: idx)
                onTextChange?(text)
            }
            resetCursorBlink()
            return
        }

        // Arrow left
        if event.keyCode == 123 {
            if mods.contains(.command) {
                cursorIndex = 0
            } else {
                cursorIndex = max(0, cursorIndex - 1)
            }
            resetCursorBlink()
            return
        }

        // Arrow right
        if event.keyCode == 124 {
            if mods.contains(.command) {
                cursorIndex = text.count
            } else {
                cursorIndex = min(text.count, cursorIndex + 1)
            }
            resetCursorBlink()
            return
        }

        // Home
        if event.keyCode == 115 {
            cursorIndex = 0
            resetCursorBlink()
            return
        }

        // End
        if event.keyCode == 119 {
            cursorIndex = text.count
            resetCursorBlink()
            return
        }

        // Cmd+A select all (just move cursor to end for now)
        if mods.contains(.command) && chars == "a" {
            cursorIndex = text.count
            resetCursorBlink()
            return
        }

        // Cmd+V paste
        if mods.contains(.command) && chars == "v" {
            if let pasted = NSPasteboard.general.string(forType: .string) {
                let clean = pasted.replacingOccurrences(of: "\n", with: " ")
                let idx = text.index(text.startIndex, offsetBy: cursorIndex)
                text.insert(contentsOf: clean, at: idx)
                cursorIndex += clean.count
                onTextChange?(text)
            }
            resetCursorBlink()
            return
        }

        // Cmd+C copy
        if mods.contains(.command) && chars == "c" {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            return
        }

        // Ignore other modifier combos (Cmd+X, etc.)
        if mods.contains(.command) || mods.contains(.control) {
            return
        }

        // Tab — move focus
        if event.keyCode == 48 {
            window?.selectNextKeyView(nil)
            return
        }

        // Regular character input
        if let input = event.characters, !input.isEmpty {
            let filtered = input.filter { !$0.isNewline }
            if !filtered.isEmpty {
                let idx = text.index(text.startIndex, offsetBy: cursorIndex)
                text.insert(contentsOf: filtered, at: idx)
                cursorIndex += filtered.count
                onTextChange?(text)
            }
        }
        resetCursorBlink()
    }

    private func resetCursorBlink() {
        cursorVisible = true
        needsDisplay = true
        startCursorBlink()
    }

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds

        if text.isEmpty && window?.firstResponder != self {
            // Draw placeholder
            let attrs: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: NSColor.white.withAlphaComponent(0.3),
            ]
            let str = NSAttributedString(string: placeholder, attributes: attrs)
            let size = str.size()
            let y = (bounds.height - size.height) / 2
            str.draw(at: NSPoint(x: 0, y: y))
            return
        }

        // Draw text
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: textColor,
        ]
        let str = NSAttributedString(string: text, attributes: attrs)
        let size = str.size()
        let y = (bounds.height - size.height) / 2
        str.draw(at: NSPoint(x: 0, y: y))

        // Draw cursor
        if window?.firstResponder == self && cursorVisible {
            let prefix = String(text.prefix(cursorIndex))
            let prefixSize = NSAttributedString(string: prefix, attributes: attrs).size()
            let cursorX = prefixSize.width
            let cursorRect = NSRect(x: cursorX, y: y, width: 1.5, height: size.height)
            textColor.withAlphaComponent(0.8).setFill()
            cursorRect.fill()
        }
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        // Place cursor at click position
        let loc = convert(event.locationInWindow, from: nil)
        let attrs: [NSAttributedString.Key: Any] = [.font: font]
        var bestIndex = text.count
        for i in 0...text.count {
            let prefix = String(text.prefix(i))
            let w = NSAttributedString(string: prefix, attributes: attrs).size().width
            if w > loc.x {
                bestIndex = max(0, i - 1)
                break
            }
        }
        cursorIndex = bestIndex
        resetCursorBlink()
    }

    func setText(_ newText: String) {
        if text != newText {
            text = newText
            cursorIndex = min(cursorIndex, text.count)
            needsDisplay = true
        }
    }
}

struct TerminalTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    var textColor: NSColor = .white
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> RawInputView {
        let view = RawInputView()
        view.font = font
        view.textColor = textColor
        view.placeholder = placeholder
        view.onTextChange = { newText in
            context.coordinator.parent.text = newText
        }
        view.onSubmit = {
            context.coordinator.parent.onSubmit()
        }
        return view
    }

    func updateNSView(_ view: RawInputView, context: Context) {
        view.setText(text)
        view.placeholder = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator {
        var parent: TerminalTextField
        init(_ parent: TerminalTextField) {
            self.parent = parent
        }
    }
}

#else
struct TerminalTextField: View {
    @Binding var text: String
    var placeholder: String = ""
    var onSubmit: () -> Void = {}

    var body: some View {
        TextField(placeholder, text: $text)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .textFieldStyle(.plain)
            .onSubmit { onSubmit() }
    }
}
#endif
