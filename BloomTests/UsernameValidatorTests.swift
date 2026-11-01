import Foundation
import Testing
@testable import Bloom

@MainActor
@Suite("Username and display name validation")
struct UsernameValidatorTests {
    @Test("Valid usernames pass", arguments: [
        "abc", "emily", "Emily_Du", "a.b.c", "user123", "___", "...",
        String(repeating: "a", count: 30),
    ])
    func valid(username: String) {
        #expect(UsernameValidator.isValid(username))
        #expect(UsernameValidator.errorMessage(for: username) == nil)
    }

    @Test("The length limits are 3 and 30 characters", arguments: [
        ("ab", false), ("abc", true), (String(repeating: "a", count: 30), true), (String(repeating: "a", count: 31), false),
    ])
    func lengthBoundaries(username: String, isValid: Bool) {
        #expect(UsernameValidator.isValid(username) == isValid)
    }

    @Test("Too short and too long give the length message", arguments: [
        "", "a", "ab", String(repeating: "a", count: 31), String(repeating: "a", count: 100),
    ])
    func lengthMessage(username: String) {
        #expect(UsernameValidator.errorMessage(for: username) == "Username must be 3 to 30 characters.")
    }

    @Test("Spaces, symbols, emoji and accents give the characters message", arguments: [
        "has space", "dash-name", "at@sign", "emoji😀name", "ab😀", "ñandu", "日本語です", "tab\tname",
    ])
    func badCharacters(username: String) {
        #expect(UsernameValidator.errorMessage(for: username)
                == "Username can only contain letters, numbers, underscore and dot.")
    }

    @Test("Blank input is a length error, not a characters error", arguments: ["", "   ", "\n"])
    func blank(username: String) {
        #expect(UsernameValidator.errorMessage(for: username) == "Username must be 3 to 30 characters.")
    }

    @Test("Surrounding spaces are trimmed before checking")
    func trimmed() {
        #expect(UsernameValidator.isValid("  emily  "))
        #expect(!UsernameValidator.isValid(" ab "))
    }

    @Test("Display names need 1 to 40 characters after trimming", arguments: [
        ("", false), ("   ", false), ("E", true), ("Emily Du 🌸", true),
        (String(repeating: "a", count: 40), true), (String(repeating: "a", count: 41), false),
    ])
    func displayName(name: String, isValid: Bool) {
        #expect(DisplayNameValidator.isValid(name) == isValid)
        #expect((DisplayNameValidator.errorMessage(for: name) == nil) == isValid)
    }
}
