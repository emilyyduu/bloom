import SwiftUI

/// The one-time SMS code entry step. Shared by both sign-up and log-in,
/// isNewAccount decides whether a Firestore user profile still needs to
/// be created once the code is confirmed.
struct PhoneVerificationView: View {
    let verificationID: String
    let username: String
    let isNewAccount: Bool

    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Enter the 6-digit code sent by SMS") {
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
            }
            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red).font(.footnote)
            }
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
        isSubmitting = true
        errorMessage = nil

        Task {
            do {
                try await AuthService.shared.confirmPhoneCode(verificationID: verificationID, code: code)
                if isNewAccount {
                    try await AuthService.shared.createUserProfile(username: username, email: nil, phoneNumber: nil)
                }
            } catch {
                errorMessage = error.localizedDescription
            }
            isSubmitting = false
        }
    }
}
