import SwiftUI

struct FunFactWidget: View {
    @Environment(\.theme) private var theme
    @State private var currentFact: String
    @State private var factIndex: Int

    private static let facts = [
        "Honey never spoils. Archaeologists found 3000-year-old honey in Egyptian tombs that was still edible.",
        "Octopuses have three hearts and blue blood.",
        "A group of flamingos is called a 'flamboyance'.",
        "The shortest war in history lasted 38 minutes (Britain vs Zanzibar, 1896).",
        "Bananas are berries, but strawberries aren't.",
        "A jiffy is an actual unit of time: 1/100th of a second.",
        "The inventor of the Pringles can is buried in one.",
        "Venus is the only planet that spins clockwise.",
        "Cows have best friends and get stressed when separated.",
        "A day on Venus is longer than a year on Venus.",
        "The total weight of ants on Earth roughly equals the total weight of humans.",
        "Oxford University is older than the Aztec Empire.",
        "Cleopatra lived closer in time to the Moon landing than to the building of the Great Pyramid.",
        "There are more possible iterations of a game of chess than atoms in the known universe.",
        "Wombat poop is cube-shaped.",
        "The longest hiccupping spree lasted 68 years.",
        "A cloud can weigh more than a million pounds.",
        "The letter 'e' appears in ~11% of all English words but not in any number from 1 to 999.",
        "Scotland's national animal is the unicorn.",
        "There are more trees on Earth than stars in the Milky Way.",
    ]

    init() {
        // Pick based on day of year for daily rotation
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        let idx = day % Self.facts.count
        _factIndex = State(initialValue: idx)
        _currentFact = State(initialValue: Self.facts[idx])
    }

    var body: some View {
        WidgetShell(title: "FUNFACT.TXT", zone: "secondary") {
            VStack(alignment: .leading, spacing: 8) {
                Text(currentFact)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(ThemeManager.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack {
                    Spacer()
                    Button {
                        factIndex = (factIndex + 1) % Self.facts.count
                        withAnimation(.easeInOut(duration: 0.2)) {
                            currentFact = Self.facts[factIndex]
                        }
                    } label: {
                        Text("tap for another >")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundColor(ThemeManager.textSecondary.opacity(0.5))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
