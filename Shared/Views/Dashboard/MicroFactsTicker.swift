import SwiftUI

/// Rotates two micro-facts from `HeroCopy.microFacts` every 6s. The prototype
/// fetches fresh LLM quips every 2h; wire that in when ClaudeService lands.
struct MicroFactsTicker: View {
    @State private var facts: [String] = HeroCopy.microFacts
    @State private var iA: Int = 0
    @State private var iB: Int = 1
    @State private var toggle: Bool = false
    private let tick = Timer.publish(every: 6, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if facts.isEmpty {
                EmptyView()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    factLine(facts[safe: iA])
                        .id("a-\(iA)")
                    if facts.count > 1 {
                        factLine(facts[safe: iB])
                            .id("b-\(iB)")
                    }
                }
            }
        }
        .onReceive(tick) { _ in
            guard !facts.isEmpty else { return }
            withAnimation(.easeInOut(duration: 0.4)) {
                if toggle { iA = (iA + 2) % facts.count }
                else { iB = (iB + 2) % facts.count }
                toggle.toggle()
            }
        }
    }

    @ViewBuilder
    private func factLine(_ text: String?) -> some View {
        HStack(spacing: 0) {
            Text("·  ")
                .foregroundColor(Color(red: 0.55, green: 0.85, blue: 0.80).opacity(0.6))
            Text(text ?? "")
                .italic()
                .foregroundColor(.white.opacity(0.78))
        }
        .font(.system(size: 11, weight: .regular, design: .monospaced))
        .tracking(0.22)
        .lineLimit(1)
        .shadow(color: .black.opacity(0.95), radius: 1, x: 0, y: 1)
        .shadow(color: .black.opacity(0.7), radius: 5, x: 0, y: 0)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? {
        (i >= 0 && i < count) ? self[i] : nil
    }
}
