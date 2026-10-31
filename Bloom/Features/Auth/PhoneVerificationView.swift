import SwiftUI
import FirebaseAuth

// The one-time SMS code entry step. Shared by both sign-up and log-in,
// isNewAccount decides whether a Firestore user profile still needs to
// be created once the code is confirmed.
struct PhoneVerificationView: View {
    // How long Resend code stays disabled after each send.
    private static let resendDelay = 30

    let phoneNumber: String
    let displayName: String
    let username: String
    let isNewAccount: Bool

    // A resend returns a new verification ID, and only the newest one
    // matches the code that was last texted.
    @State private var verificationID: String
    @State private var code = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var secondsUntilResend = PhoneVerificationView.resendDelay
    // Bumped on every send so the countdown task restarts.
    @State private var sendCount = 0

    init(verificationID: String, phoneNumber: String, displayName: String, username: String, isNewAccount: Bool) {
        _verificationID = State(initialValue: verificationID)
        self.phoneNumber = phoneNumber
        self.displayName = displayName
        self.username = username
        self.isNewAccount = isNewAccount
    }

    private var shownNumber: String {
        phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Form {
            Section {
                TextField("123456", text: $code)
                    .keyboardType(.numberPad)
                    .textContentType(.oneTimeCode)
            } header: {
                SectionHeader("Enter the 6 digit code we sent to \(shownNumber)")
            }

            Section {
                Button("Resend code") { resend() }
                    .disabled(isSubmitting || secondsUntilResend > 0)
            } footer: {
                if secondsUntilResend > 0 {
                    Text("You can ask for a new code in \(secondsUntilResend) seconds.")
                        .monospacedDigit()
                }
            }

            AuthErrorText(message: errorMessage)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Verify")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Verify") { verify() }
                    .disabled(isSubmitting || code.count < 6)
            }
        }
        // Runs on appear (the first code was just sent) and again after
        // each resend. Cancelled automatically when the screen goes away.
        .task(id: sendCount) {
            secondsUntilResend = Self.resendDelay
            while secondsUntilResend > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }
                secondsUntilResend -= 1
            }
        }
    }

    private func verify() {
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            try await AuthService.shared.confirmPhoneCode(verificationID: verificationID, code: code)
            if isNewAccount {
                let phoneNumber = Auth.auth().currentUser?.phoneNumber.map(PhoneNumber.normalized)
                try await AuthService.shared.createUserProfile(displayName: displayName, username: username, phoneNumber: phoneNumber)
            }
        }
    }

    // Sends a fresh code to the same number. The countdown only restarts
    // once the send succeeds.
    private func resend() {
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            verificationID = try await AuthService.shared.startPhoneVerification(phoneNumber: phoneNumber)
            code = ""
            sendCount += 1
        }
    }
}
