import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Changes the display name and username on the users document. The
// Firestore rules for that document only allow displayName, username,
// usernameLower, phoneNumber and createdAt, so displayName, username and
// usernameLower are always written together, and this also clears any
// leftover "email" field with FieldValue.delete() rather than ever
// writing one.
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var displayName: String
    @State private var username: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    @StateObject private var myAvatar = MyAvatar.shared

    private let originalDisplayName: String
    private let originalUsername: String
    let onSave: (_ displayName: String, _ username: String) -> Void

    init(displayName: String, username: String, onSave: @escaping (_ displayName: String, _ username: String) -> Void) {
        _displayName = State(initialValue: displayName)
        _username = State(initialValue: username)
        originalDisplayName = displayName
        originalUsername = username
        self.onSave = onSave
    }

    private var trimmedDisplayName: String {
        displayName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // Unlike Sign Up, an empty display name does show its error here:
    // the field starts filled in, so empty means it was cleared.
    private var displayNameValidationError: String? {
        DisplayNameValidator.errorMessage(for: trimmedDisplayName)
    }

    private var usernameValidationError: String? {
        guard !trimmedUsername.isEmpty else { return nil }
        return UsernameValidator.errorMessage(for: trimmedUsername)
    }

    private var isValid: Bool {
        DisplayNameValidator.isValid(trimmedDisplayName) && UsernameValidator.isValid(trimmedUsername)
    }

    private var hasChanges: Bool {
        trimmedDisplayName != originalDisplayName || trimmedUsername != originalUsername
    }

    var body: some View {
        Form {
            // The photo saves on its own as soon as it's chosen, it
            // isn't part of the Save button below.
            Section {
                VStack(spacing: Theme.Spacing.sm) {
                    EditableAvatar(
                        model: myAvatar,
                        uid: Auth.auth().currentUser?.uid,
                        name: trimmedDisplayName.isEmpty ? originalDisplayName : trimmedDisplayName,
                        size: 96,
                        relativeTo: .largeTitle,
                        maxSize: 140
                    )
                    FormErrorText(message: myAvatar.errorMessage)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .listRowBackground(Color.clear)
            }

            Section {
                TextField("Display name", text: $displayName)
                    .textContentType(.name)
                    .textInputAutocapitalization(.words)
                if let displayNameValidationError {
                    Text(displayNameValidationError)
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Colors.error)
                }
            } header: {
                SectionHeader("Display name")
            } footer: {
                Text("This is the name friends see. Your username is how they find you.")
            }

            Section {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if let usernameValidationError {
                    Text(usernameValidationError)
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Colors.error)
                }
            } header: {
                SectionHeader("Username")
            }

            FormErrorText(message: errorMessage)
        }
        .navigationTitle("Edit Profile")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                if isSaving {
                    ProgressView()
                } else {
                    Button("Save") { save() }
                        .disabled(!isValid || !hasChanges)
                }
            }
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let newDisplayName = trimmedDisplayName
        let newUsername = trimmedUsername

        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await Firestore.firestore().collection("users").document(uid).updateData([
                    "displayName": newDisplayName,
                    "username": newUsername,
                    "usernameLower": newUsername.lowercased(),
                    "email": FieldValue.delete(),
                ])
                onSave(newDisplayName, newUsername)
                dismiss()
            } catch {
                errorMessage = "Couldn't save your changes. \(error.localizedDescription)"
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        EditProfileView(displayName: "Bloom User", username: "bloom_user") { _, _ in }
    }
}
