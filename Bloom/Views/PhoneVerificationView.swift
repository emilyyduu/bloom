import SwiftUI
import FirebaseAuth

// The one-time SMS code entry step. Shared by both sign-up and log-in,
// isNewAccount decides whether a Firestore user profile still needs to
// be created once the code is confirmed.
struct PhoneVerificationView: View {
    let verificationID: String
    let username: String
    let isNewAccount: Bool

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
            } header: {
                SectionHeader("Enter the 6-digit code sent by SMS")
            }
            FormErrorText(message: errorMessage)
        }
        .navigationTitle("Verify")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Verify") { verify() }
                    .disabled(isSubmitting || code.count < 6)
            }
        }
    }

    private func verify() {
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            try await AuthService.shared.confirmPhoneCode(verificationID: verificationID, code: code)
            if isNewAccount {
                let phoneNumber = Auth.auth().currentUser?.phoneNumber.map(PhoneNumber.normalized)
                try await AuthService.shared.createUserProfile(username: username, phoneNumber: phoneNumber)
            }
        }
    }
}
