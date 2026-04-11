import Foundation

@Observable
final class ScratchpadService {
    private let icloud = iCloudService.shared
    private(set) var scratchpad = ScratchpadFile()

    init() {
        reload()
    }

    func reload() {
        guard let content = icloud.readFile(at: icloud.scratchpadURL) else { return }
        scratchpad = MarkdownParser.parseScratchpad(content)
    }

    func addLine(_ line: String) {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let content = icloud.readFile(at: icloud.scratchpadURL) ?? ""
        let updated = MarkdownParser.appendToScratchpad(content, line: line)
        icloud.writeFile(at: icloud.scratchpadURL, content: updated)
        reload()
    }
}
