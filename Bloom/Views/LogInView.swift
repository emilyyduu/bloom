import SwiftUI

// Log-in for a returning user. No username field here, that's only
// needed once, at sign-up.
struct LogInView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var method: AuthMethod = .phone
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var verificationID: String?

    var body: some View {
        NavigationStack {
            Form {
                AuthMethodPicker(method: $method)

                switch method {
                case .phone:
                    Section {
                        TextField("+61 4xx xxx xxx", text: $phoneNumber)
                            .keyboardType(.phonePad)
                    } header: {
                        SectionHeader("Phone Number")
                    }
                case .email:
                    Section {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                        SecureField("Password", text: $password)
                    } header: {
                        SectionHeader("Email & Password")
                    }
                }

                FormErrorText(message: errorMessage)
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .navigationTitle("Log In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(method == .phone ? "Send Code" : "Log In") { submit() }
                        .disabled(isSubmitting)
                }
            }
            .navigationDestination(item: $verificationID) { id in
                PhoneVerificationView(verificationID: id, username: "", isNewAccount: false)
            }
        }
    }

    private func submit() {
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            switch method {
            case .phone:
                verificationID = try await AuthService.shared.startPhoneVerification(phoneNumber: phoneNumber)
            case .email:
                try await AuthService.shared.signInWithEmail(email: email, password: password)
            }
        }
    }
}
