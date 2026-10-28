import Foundation

// The username rule shared by Sign Up and Edit Profile: 3 to 30
// characters, letters, numbers, underscore and dot only. Kept in one
// place so client-side validation never drifts from what the Firestore
// security rules accept, and usernameLower stays a faithful lowercase
// copy of whatever's actually allowed.
enum UsernameValidator {
    private static let allowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_."
    )

    static func errorMessage(for username: String) -> String? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)

        guard (3...30).contains(trimmed.count) else {
            return "Username must be 3 to 30 characters."
        }
        guard trimmed.unicodeScalars.allSatisfy({ allowedCharacters.contains($0) }) else {
            return "Username can only contain letters, numbers, underscore and dot."
        }
        return nil
    }

    static func isValid(_ username: String) -> Bool {
        errorMessage(for: username) == nil
    }
}

// The display name rule shared by Sign Up and Edit Profile: 1 to 40
// characters after trimming, anything goes.
enum DisplayNameValidator {
    static func errorMessage(for displayName: String) -> String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        return (1...40).contains(trimmed.count) ? nil : "Display name must be 1 to 40 characters."
    }

    static func isValid(_ displayName: String) -> Bool {
        errorMessage(for: displayName) == nil
    }
}
