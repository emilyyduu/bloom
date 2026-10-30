import Foundation

// Normalizes a phone number into one comparable form: digits only,
// country calling code included, no "+". Used both when a phone
// account's number is saved and when a device contact's number is
// checked against it, so the two can't drift into different formats.
enum PhoneNumber {
    // A small hardcoded lookup rather than a full phone number library,
    // since this only needs to cover sign-up on these regions.
    private static let callingCodesByRegion: [String: String] = [
        "AU": "61",
        "NZ": "64",
        "US": "1",
        "CA": "1",
        "GB": "44",
    ]

    private static let defaultCallingCode = callingCodesByRegion["AU"]!

    // "+61 400 000 001" and "0061 400 000 001" both become
    // "61400000001". A local number like "0400 000 001" becomes the
    // same thing too, using the device's region to fill in the country
    // calling code.
    static func normalized(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let digits = trimmed.filter(\.isNumber)

        if trimmed.hasPrefix("+") {
            return digits
        }
        if trimmed.hasPrefix("00") {
            return String(digits.dropFirst(2))
        }
        if trimmed.hasPrefix("0") {
            let region = Locale.current.region?.identifier ?? ""
            let callingCode = callingCodesByRegion[region] ?? defaultCallingCode
            return callingCode + digits.dropFirst()
        }
        return digits
    }
}
