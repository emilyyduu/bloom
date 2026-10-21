import SwiftUI
import PhotosUI
import SwiftData
import FirebaseAuth

// Lets the user write a note, optionally attach a photo, and either save
// it as a draft or add it straight to today's journal. Adding a note is
// immediate, there is nothing further to publish.
struct NoteComposerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @State private var text: String = ""
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isSharedWithFriends: Bool

    // Starts from the "Share new notes with friends" setting, so a
    // note only needs the switch flipped by hand when it should
    // differ from that default.
    init() {
        _isSharedWithFriends = State(initialValue: UserDefaults.standard.bool(forKey: "shareNewNotesWithFriends"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 120)
                } header: {
                    SectionHeader("What's happening?")
                }

                Section {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                        Label(
                            selectedPhotoData == nil ? "Add a photo" : "Change photo",
                            systemImage: "photo"
                        )
                    }

                    if let selectedPhotoData, let uiImage = UIImage(data: selectedPhotoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .frame(maxHeight: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                } header: {
                    SectionHeader("Photo")
                }

                Section {
                    Toggle("Share with friends", isOn: $isSharedWithFriends)
                } footer: {
                    Text("Everyone in your circle can read notes you share. This does not apply to drafts.")
                }
            }
            .navigationTitle("New Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add to Today") { save(asDraft: false) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                ToolbarItem(placement: .bottomBar) {
                    Button("Save as Draft") { save(asDraft: true) }
                        .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else { return }
                selectedPhotoData = try? await selectedPhotoItem.loadTransferable(type: Data.self)
            }
        }
    }

    private func save(asDraft: Bool) {
        var photoFileName: String?
        if let selectedPhotoData {
            photoFileName = try? writePhotoToDisk(selectedPhotoData)
        }

        let note = Note.createDraft(in: context, text: text, photoFileName: photoFileName)
        note.isDraft = asDraft

        if !asDraft {
            let journal = Journal.journal(for: Date(), in: context)
            note.journal = journal
        }

        note.ownerUID = Auth.auth().currentUser?.uid
        // A draft is never shared, the security rules reject it.
        note.sharedWithFriends = asDraft ? false : isSharedWithFriends

        try? context.save()

        if !asDraft {
            NotificationScheduler.shared.cancelTodaysReminder()
            Task { await StreakSyncService.shared.sync(context: context) }
        }

        NoteSyncService.shared.upload(note)

        dismiss()
    }

    private func writePhotoToDisk(_ data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let url = FileManager.documentsDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return fileName
    }
}

#Preview {
    NoteComposerView()
        .modelContainer(PreviewContainer.shared)
}
