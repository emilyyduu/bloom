import Foundation

// Where the published Terms of Use and Privacy Policy live. These are
// placeholder addresses: replace both once the documents are hosted, this is
// the only place they are written down. Sign up and About read them from here.
enum LegalLinks {
    static let terms = "https://example.com/bloom/terms"
    static let privacyPolicy = "https://example.com/bloom/privacy"

    static let termsURL = URL(string: terms)
    static let privacyPolicyURL = URL(string: privacyPolicy)

    // The sentence beside the sign up checkbox, with both documents as links.
    static var agreementText: AttributedString {
        let markdown = "I'm 16 or older and agree to the [Terms of Use](\(terms)) and [Privacy Policy](\(privacyPolicy))."
        return (try? AttributedString(markdown: markdown))
            ?? AttributedString("I'm 16 or older and agree to the Terms of Use and Privacy Policy.")
    }

    static let agreementRequiredMessage = "Confirm that you are 16 or older and agree to the Terms of Use and Privacy Policy to sign up."
}
