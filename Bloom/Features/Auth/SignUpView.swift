import SwiftUI

// Signing up asks for phone or email first, then only shows the fields
// for whichever one is picked, rather than presenting one long form.
struct SignUpView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var method: AuthMethod = .phone
    @State private var displayName = ""
    @State private var username = ""
    @State private var phoneNumber = ""
    @State private var email = ""
    @State private var password = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var verificationID: String?

    // Only shown once something is typed, like the username error, so
    // an untouched form isn't covered in red.
    private var displayNameValidationError: String? {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return DisplayNameValidator.errorMessage(for: trimmed)
    }

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
                    .accessibilityIdentifier("signUp.method")

                Section {
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .accessibilityIdentifier("signUp.displayName")
                    if let displayNameValidationError {
                        Text(displayNameValidationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("signUp.displayNameError")
                    }
                } header: {
                    SectionHeader("Display name")
                } footer: {
                    Text("This is the name friends see. Your username is how they find you.")
                }

                Section {
                    TextField("Username", text: $username)
                        .textInputAutocapitalization(.never)
                        .accessibilityIdentifier("signUp.username")
                    if let usernameValidationError {
                        Text(usernameValidationError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("signUp.usernameError")
                    }
                } header: {
                    SectionHeader("Username")
                }

                switch method {
                case .phone:
                    Section {
                        TextField("+61 4xx xxx xxx", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .accessibilityIdentifier("signUp.phone")
                    } header: {
                        SectionHeader("Phone Number")
                    }
                case .email:
                    Section {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .accessibilityIdentifier("signUp.email")
                        SecureField("Password", text: $password)
                            .accessibilityIdentifier("signUp.password")
                    } header: {
                        SectionHeader("Email & Password")
                    }
                }

                FormErrorText(message: errorMessage)
                    .accessibilityIdentifier("signUp.error")
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .navigationTitle("Sign Up")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("signUp.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(method == .phone ? "Send Code" : "Sign Up") { submit() }
                        .disabled(isSubmitting || !isUsernameValid || !DisplayNameValidator.isValid(displayName))
                        .accessibilityIdentifier("signUp.submit")
                }
            }
            .navigationDestination(item: $verificationID) { id in
                PhoneVerificationView(verificationID: id, displayName: displayName, username: username, isNewAccount: true)
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
                try await AuthService.shared.createUserProfile(displayName: displayName, username: username, phoneNumber: nil)
            }
        }
    }
}

#Preview {
    SignUpView()
}
