import SwiftUI

// Settings > Delete account. Says what will be erased, asks the person to
// sign in again (Firebase requires it before deleting an account), then
// deletes after one more confirmation. When it succeeds the sign in is gone
// and the app returns to the Welcome screen by itself.
struct DeleteAccountView: View {
    @State private var password = ""
    @State private var code = ""
    @State private var verificationID: String?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @State private var isShowingConfirmation = false
    @FocusState private var isFieldFocused: Bool

    private var method: AuthService.ReauthMethod? { AuthService.shared.reauthMethod }

    private var canDelete: Bool {
        switch method {
        case .password: return !password.isEmpty
        case .phone: return verificationID != nil && code.count >= 6
        case nil: return false
        }
    }

    var body: some View {
        Form {
            Section {
                Text("Deleting your account permanently erases:")
                ForEach(Self.erasedItems, id: \.self) { item in
                    Label(item, systemImage: "minus")
                }
                Text("This cannot be undone. Friends will no longer see you or anything you shared.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            } header: {
                SectionHeader("What happens")
            }

            switch method {
            case .password:
                Section {
                    SecureField("Password", text: $password)
                        .textContentType(.password)
                        .focused($isFieldFocused)
                        .submitLabel(.done)
                        .accessibilityIdentifier("deleteAccount.password")
                } header: {
                    SectionHeader("Confirm it is you")
                } footer: {
                    Text("Enter your password.")
                }
            case .phone:
                Section {
                    Button(verificationID == nil ? "Send code" : "Send a new code") { sendCode() }
                        .disabled(isSubmitting)
                        .frame(minHeight: 44, alignment: .leading)
                    if verificationID != nil {
                        TextField("123456", text: $code)
                            .keyboardType(.numberPad)
                            .textContentType(.oneTimeCode)
                            .focused($isFieldFocused)
                            .accessibilityIdentifier("deleteAccount.code")
                    }
                } header: {
                    SectionHeader("Confirm it is you")
                } footer: {
                    Text("We will text a 6 digit code to the number on your account.")
                }
            case nil:
                Section {
                    Text("Sign out and sign in again, then try once more.")
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
            }

            Section {
                Button(role: .destructive) {
                    isFieldFocused = false
                    isShowingConfirmation = true
                } label: {
                    HStack {
                        Text("Delete my account")
                        if isSubmitting {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSubmitting || !canDelete)
                .frame(minHeight: 44, alignment: .leading)
                .accessibilityIdentifier("deleteAccount.delete")

                AuthErrorText(message: errorMessage)
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Delete account")
        .navigationBarTitleDisplayMode(.inline)
        .interactiveDismissDisabled(isSubmitting)
        .navigationBarBackButtonHidden(isSubmitting)
        .alert(
            "Delete your account permanently?",
            isPresented: $isShowingConfirmation
        ) {
            Button("Delete Account", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your notes, photos, voice memos, friends and profile will be erased. This cannot be undone.")
        }
    }

    private static let erasedItems = [
        "Your profile, picture, username and streak",
        "Your notes, photos and voice memos, on this device and in your backup",
        "Your friend requests and friendships",
        "Your circles and your notification feed",
        "Your comments and reactions on friends' notes",
    ]

    private func sendCode() {
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            verificationID = try await AuthService.shared.startPhoneReauthentication()
            code = ""
        }
    }

    private func deleteAccount() {
        performSubmission(isSubmitting: $isSubmitting, errorMessage: $errorMessage) {
            switch method {
            case .password:
                try await AuthService.shared.reauthenticate(password: password)
            case .phone:
                guard let verificationID else { throw AuthService.AuthServiceError.cannotReauthenticate }
                try await AuthService.shared.reauthenticate(verificationID: verificationID, code: code)
            case nil:
                throw AuthService.AuthServiceError.cannotReauthenticate
            }
            try await AccountDeletionService.shared.deleteAccount()
        }
    }
}

#Preview {
    NavigationStack { DeleteAccountView() }
}
