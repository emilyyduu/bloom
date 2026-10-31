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
    @State private var hasAgreed = false
    @FocusState private var focusedField: Field?

    // The order Return moves through the fields on this form.
    private enum Field {
        case displayName, username, phone, email, password
    }

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
                Section {
                    AuthMethodPicker(method: $method)
                        .accessibilityIdentifier("signUp.method")
                } header: {
                    SectionHeader("Sign up with")
                }

                Section {
                    TextField("Display name", text: $displayName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
                        .focused($focusedField, equals: .displayName)
                        .submitLabel(.next)
                        .onSubmit { focusedField = .username }
                        .accessibilityIdentifier("signUp.displayName")
                    if let displayNameValidationError {
                        AuthErrorText(message: displayNameValidationError)
                            .accessibilityIdentifier("signUp.displayNameError")
                    }
                } header: {
                    SectionHeader("Display name")
                } footer: {
                    Text("This is the name friends see. Your username is how they find you.")
                }

                Section {
                    TextField("Username", text: $username)
                        .textContentType(.username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .focused($focusedField, equals: .username)
                        .submitLabel(.next)
                        .onSubmit { focusedField = method == .phone ? .phone : .email }
                        .accessibilityIdentifier("signUp.username")
                    if let usernameValidationError {
                        AuthErrorText(message: usernameValidationError)
                            .accessibilityIdentifier("signUp.usernameError")
                    }
                } header: {
                    SectionHeader("Username")
                } footer: {
                    Text("Friends can search for you by username. Use letters, numbers, underscore or dot.")
                }

                switch method {
                case .phone:
                    Section {
                        TextField("+61 4xx xxx xxx", text: $phoneNumber)
                            .keyboardType(.phonePad)
                            .textContentType(.telephoneNumber)
                            .focused($focusedField, equals: .phone)
                            .accessibilityIdentifier("signUp.phone")
                    } header: {
                        SectionHeader("Phone number")
                    } footer: {
                        Text("We'll text you a 6 digit code. No password needed.")
                    }
                case .email:
                    Section {
                        TextField("Email", text: $email)
                            .keyboardType(.emailAddress)
                            .textContentType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focusedField, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { focusedField = .password }
                            .accessibilityIdentifier("signUp.email")
                        SecureField("Password", text: $password)
                            .textContentType(.newPassword)
                            .focused($focusedField, equals: .password)
                            .submitLabel(.go)
                            .onSubmit { submitIfReady() }
                            .accessibilityIdentifier("signUp.password")
                    } header: {
                        SectionHeader("Email and password")
                    } footer: {
                        Text("Choose a password with at least 6 characters.")
                    }
                }

                Section {
                    Toggle(isOn: $hasAgreed) {
                        Text(LegalLinks.agreementText)
                            .textStyle(.callout)
                    }
                    .accessibilityIdentifier("signUp.agree")
                }

                AuthErrorText(message: errorMessage)
                    .accessibilityIdentifier("signUp.error")
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
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
                PhoneVerificationView(
                    verificationID: id,
                    phoneNumber: phoneNumber,
                    displayName: displayName,
                    username: username,
                    isNewAccount: true
                )
            }
        }
    }

    // Return on the last field does what the toolbar button does, but only
    // when that button would be enabled.
    private func submitIfReady() {
        guard !isSubmitting, isUsernameValid, DisplayNameValidator.isValid(displayName) else { return }
        submit()
    }

    private func submit() {
        guard hasAgreed else {
            errorMessage = LegalLinks.agreementRequiredMessage
            return
        }
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            switch method {
            case .phone:
                verificationID = try await AuthService.shared.startPhoneVerification(phoneNumber: phoneNumber)
            case .email:
                try await AuthService.shared.signUpWithEmail(email: email, password: password)
                try await AuthService.shared.completeSignUp(displayName: displayName, username: username)
            }
        }
    }
}

#Preview {
    SignUpView()
}
