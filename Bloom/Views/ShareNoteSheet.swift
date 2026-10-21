import SwiftUI

// The per-note sharing control, reached from the share button on a
// note already saved (Home's timeline, Flipbook). Replaces the old
// ShareToFriendView flow now that sharing is a flag on the note's
// Firestore backup rather than a separate sharedNotes write.
struct ShareNoteSheet: View {
    @Bindable var note: Note
    @Environment(\.dismiss) private var dismiss

    @State private var isUpdating = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle(
                        "Share with friends",
                        isOn: Binding(
                            get: { note.sharedWithFriends },
                            set: { updateSharing(to: $0) }
                        )
                    )
                    .disabled(isUpdating)
                } footer: {
                    Text("All your accepted friends can read this note.")
                }

                FormErrorText(message: errorMessage)
            }
            .navigationTitle("Share Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func updateSharing(to isShared: Bool) {
        errorMessage = nil
        isUpdating = true
        Task {
            do {
                try await NoteSyncService.shared.updateSharedWithFriends(isShared, for: note)
            } catch {
                errorMessage = "Couldn't update sharing. Check your connection and try again."
            }
            isUpdating = false
        }
    }
}

// A small, non-colour-only badge for a note that's currently shared
// with friends. Pairs the SF Symbol with the word "Shared" so the
// state doesn't rely on colour alone.
struct SharedIndicator: View {
    var body: some View {
        Label("Shared", systemImage: "person.2.fill")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}

#Preview {
    ShareNoteSheet(note: Note(text: "Walked past the jacaranda trees on the way home."))
}
