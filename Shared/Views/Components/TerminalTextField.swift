import SwiftUI

/// A text field styled for terminal/monospace input that works through the
/// normal Cocoa text system (no yellow "no entry" icon on unsigned builds).
/// Disables autocorrect, spell-check, and suggestions via NSTextFieldDelegate.

#if os(macOS)

struct TerminalTextField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: NSFont = .monospacedSystemFont(ofSize: 11, weight: .regular)
    var textColor: NSColor = .white
    var onSubmit: () -> Void = {}

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.stringValue = text
        field.placeholderString = placeholder
        field.font = font
        field.textColor = textColor
        field.backgroundColor = .clear
        field.isBordered = false
        field.focusRingType = .none
        field.drawsBackground = false
        field.lineBreakMode = .byTruncatingTail
        field.cell?.wraps = false
        field.cell?.isScrollable = true
        field.delegate = context.coordinator

        // Disable text completion
        field.isAutomaticTextCompletionEnabled = false

        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        if field.stringValue != text {
            field.stringValue = text
        }
        field.placeholderString = placeholder
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: TerminalTextField

        init(_ parent: TerminalTextField) {
            self.parent = parent
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let field = obj.object as? NSTextField else { return }
            parent.text = field.stringValue
        }

        func controlTextDidBeginEditing(_ obj: Notification) {
            guard let field = obj.object as? NSTextField,
                  let editor = field.currentEditor() as? NSTextView else { return }
            editor.isAutomaticQuoteSubstitutionEnabled = false
            editor.isAutomaticDashSubstitutionEnabled = false
            editor.isAutomaticTextReplacementEnabled = false
            editor.isAutomaticSpellingCorrectionEnabled = false
            editor.isContinuousSpellCheckingEnabled = false
            editor.isGrammarCheckingEnabled = false
            editor.isAutomaticLinkDetectionEnabled = false
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
            if commandSelector == #selector(NSResponder.insertNewline(_:)) {
                parent.onSubmit()
                return true
            }
            return false
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
