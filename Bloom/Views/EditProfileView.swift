import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Changes the username on the users document. The Firestore rules for
// that document only allow username, phoneNumber and createdAt, so
// this also clears any leftover "email" field with FieldValue.delete()
// rather than ever writing one.
struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var username: String
    @State private var errorMessage: String?
    @State private var isSaving = false
    let onSave: (String) -> Void

    init(username: String, onSave: @escaping (String) -> Void) {
        _username = State(initialValue: username)
        self.onSave = onSave
    }

    private var isValid: Bool {
        let count = username.trimmingCharacters(in: .whitespacesAndNewlines).count
        return (1...30).contains(count)
    }

    var body: some View {
        Form {
            Section("Username") {
                TextField("Username", text: $username)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
                        .disabled(!isValid)
                }
            }
        }
    }

    private func save() {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)

        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await Firestore.firestore().collection("users").document(uid).updateData([
                    "username": trimmed,
                    "email": FieldValue.delete(),
                ])
                onSave(trimmed)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}

#Preview {
    NavigationStack {
        EditProfileView(username: "bloom_user") { _ in }
    }
}
