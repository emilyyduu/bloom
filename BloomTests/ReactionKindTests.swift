import Foundation
import Testing
@testable import Bloom

@MainActor
@Suite("Reaction kinds")
struct ReactionKindTests {
    @Test("There are exactly six reactions, in a fixed order")
    func sixReactions() {
        #expect(ReactionKind.allCases.map(\.rawValue) == ["love", "laugh", "wow", "sad", "clap", "sprout"])
    }

    @Test("Each stored value maps to its emoji", arguments: [
        ("love", "\u{2764}\u{FE0F}"), ("laugh", "\u{1F606}"), ("wow", "\u{1F62E}"),
        ("sad", "\u{1F622}"), ("clap", "\u{1F44F}"), ("sprout", "\u{1F331}"),
    ])
    func emojiMapping(raw: String, emoji: String) throws {
        let kind = try #require(ReactionKind(rawValue: raw))
        #expect(kind.emoji == emoji)
    }

    @Test("Unknown stored values don't become a reaction", arguments: ["", "LOVE", "like", "heart", " love"])
    func unknownRaw(raw: String) {
        #expect(ReactionKind(rawValue: raw) == nil)
    }

    @Test("The id is the raw value, and every emoji and title is distinct")
    func identity() {
        for kind in ReactionKind.allCases {
            #expect(kind.id == kind.rawValue)
            #expect(!kind.title.isEmpty)
        }
        #expect(Set(ReactionKind.allCases.map(\.emoji)).count == 6)
        #expect(Set(ReactionKind.allCases.map(\.title)).count == 6)
    }
}
