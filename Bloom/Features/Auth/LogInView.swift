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
                Section {
                    AuthMethodPicker(method: $method)
                        .accessibilityIdentifier("logIn.method")
                } header: {
                    SectionHeader("Log in with")
                }

                switch method {
                case .phone:
                    Section {
                        TextField("+61 4xx xxx xxx", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .accessibilityIdentifier("logIn.phone")
                    } header: {
                        SectionHeader("Phone number")
                    } footer: {
                        Text("We'll text you a 6 digit code. No password needed.")
                    }
                case .email:
                    Section {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("logIn.email")
                        SecureField("Password", text: $password)
                            .accessibilityIdentifier("logIn.password")
                    } header: {
                        SectionHeader("Email and password")
                    } footer: {
                        Text("Use the email and password you signed up with.")
                    }
                }

                AuthErrorText(message: errorMessage)
                    .accessibilityIdentifier("logIn.error")
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .navigationTitle("Log In")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("logIn.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(method == .phone ? "Send Code" : "Log In") { submit() }
                        .disabled(isSubmitting || isInputEmpty)
                        .accessibilityIdentifier("logIn.submit")
                }
            }
            .navigationDestination(item: $verificationID) { id in
                PhoneVerificationView(
                    verificationID: id,
                    phoneNumber: phoneNumber,
                    displayName: "",
                    username: "",
                    isNewAccount: false
                )
            }
        }
    }

    // True when the active method's fields are empty after trimming.
    private var isInputEmpty: Bool {
        switch method {
        case .phone:
            return phoneNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .email:
            return email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || password.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
