import SwiftUI

// Signing up asks for phone or email first, then only shows the fields
// for whichever one is picked, rather than presenting one long form.
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var method: AuthMethod = .phone
    @State private var username = ""
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var verificationID: String?

    private var usernameValidationError: String? {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return UsernameValidator.errorMessage(for: trimmed)
    }

    private var isUsernameValid: Bool {
        UsernameValidator.isValid(username.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            Form {
                AuthMethodPicker(method: $method)

                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                    if let usernameValidationError {
                        Text(usernameValidationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } header: {
                    SectionHeader("Username")
                }

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
            .navigationTitle("Sign Up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(method == .phone ? "Send Code" : "Sign Up") { submit() }
                        .disabled(isSubmitting || !isUsernameValid)
                }
            }
            .navigationDestination(item: $verificationID) { id in
                PhoneVerificationView(verificationID: id, username: username, isNewAccount: true)
            }
        }
    }

    private func submit() {
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            switch method {
            case .phone:
                verificationID = try await AuthService.shared.startPhoneVerification(phoneNumber: phoneNumber)
            case .email:
                try await AuthService.shared.signUpWithEmail(email: email, password: password)
                try await AuthService.shared.createUserProfile(username: username, phoneNumber: nil)
            }
        }
    }
}

#Preview {
    SignUpView()
}
