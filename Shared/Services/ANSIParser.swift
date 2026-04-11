import Foundation

/// Strips ANSI escape codes from terminal output so the UI shows clean text.
struct ANSIParser {
    /// Remove all ANSI escape sequences from the given string.
    static func strip(_ text: String) -> String {
        var result = text
        // CSI sequences: ESC [ ... final byte
        result = result.replacingOccurrences(
            of: "\\x1B\\[[0-9;]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        // OSC sequences: ESC ] ... BEL
        result = result.replacingOccurrences(
            of: "\\x1B\\].*?\\x07",
            with: "",
            options: .regularExpression
        )
        // Character set selection: ESC ( or ) followed by A/B/0/1/2
        result = result.replacingOccurrences(
            of: "\\x1B[()][AB012]",
            with: "",
            options: .regularExpression
        )
        // Strip any remaining bare ESC characters
        result = result.replacingOccurrences(of: "\u{1B}", with: "")
        return result
    }
}
