import Foundation

@Observable
final class MemoryService {
    private let icloud = iCloudService.shared
    private(set) var memory = MemoryFile()

    init() {
        reload()
    }

    func reload() {
        guard let content = icloud.readFile(at: icloud.memoryURL) else { return }
        memory = MarkdownParser.parseMemory(content)
    }
}
