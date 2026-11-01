import Foundation
import Testing
@testable import Bloom

@MainActor
@Suite("Phone number normalising")
struct PhoneNumberTests {
    @Test("International formats become digits with the country code", arguments: [
        "+61 400 000 001",
        "0061 400 000 001",
        "+61400000001",
        "+61 (400) 000-001",
        "  +61 400 000 001  ",
    ])
    func internationalFormats(raw: String) {
        #expect(PhoneNumber.normalized(raw) == "61400000001")
    }

    @Test("Other countries keep their own calling code", arguments: [
        ("+64 21 123 4567", "64211234567"),
        ("+1 415 555 0100", "14155550100"),
        ("0044 20 7946 0958", "442079460958"),
    ])
    func otherCountries(raw: String, expected: String) {
        #expect(PhoneNumber.normalized(raw) == expected)
    }

    // The leading 0 is replaced by a calling code chosen from the device's
    // region (Australia when the region isn't in the table), which the
    // function doesn't let a test set. So this checks the shape: the 0 is
    // gone, the rest of the digits are kept, and a calling code is in front.
    @Test("A local number drops its leading 0 and gains a calling code")
    func localNumber() {
        let result = PhoneNumber.normalized("0400 000 001")
        let knownCodes = ["61", "64", "1", "44"]
        #expect(result.hasSuffix("400000001"))
        #expect(knownCodes.contains(String(result.dropLast("400000001".count))))
    }

    @Test("Local and international forms of the same AU number agree when the device region is AU")
    func localMatchesInternationalInAU() throws {
        try #require(Locale.current.region?.identifier == "AU" || Locale.current.region == nil,
                     "Only meaningful on an Australian (or unknown region) device")
        #expect(PhoneNumber.normalized("0400 000 001") == PhoneNumber.normalized("+61 400 000 001"))
    }

    @Test("A number with no prefix is just its digits")
    func noPrefix() {
        #expect(PhoneNumber.normalized("400 000 001") == "400000001")
    }

    @Test("Empty and blank input give an empty string", arguments: ["", " ", "   \n "])
    func emptyInput(raw: String) {
        #expect(PhoneNumber.normalized(raw).isEmpty)
    }

    @Test("Letters and punctuation are dropped")
    func lettersDropped() {
        #expect(PhoneNumber.normalized("+61 400 abc 001") == "61400001")
        #expect(PhoneNumber.normalized("call me") == "")
    }

    @Test("Short input is returned as is, without crashing", arguments: [
        ("+", ""), ("+6", "6"), ("00", ""), ("5", "5"),
    ])
    func shortInput(raw: String, expected: String) {
        #expect(PhoneNumber.normalized(raw) == expected)
    }
}
