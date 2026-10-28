import SwiftUI
import PhotosUI
import SwiftData
import FirebaseAuth

// Lets the user write a note, optionally attach a photo, and either
// save it as a draft or add it straight to today's journal. Adding a
// note is immediate, there is nothing further to publish. Pass an
// existing draft to edit it in place instead of creating a new note.
struct NoteComposerView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    private let draft: Note?
    private let originalText: String

    @State private var text: String
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isSharedWithFriends: Bool
    @State private var hasPickedNewPhoto = false
    @State private var isPhotoRemoved = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingDeleteConfirmation = false

    // Starts from the "Share new notes with friends" setting, so a
    // note only needs the switch flipped by hand when it should
    // differ from that default. Prefills text and photo when editing
    // an existing draft.
    init(draft: Note? = nil) {
        self.draft = draft
        let initialText = draft?.text ?? ""
        originalText = initialText
        _text = State(initialValue: initialText)
        _isSharedWithFriends = State(initialValue: UserDefaults.standard.bool(forKey: "shareNewNotesWithFriends"))

        if let photo = draft?.photo, let data = photo.jpegData(compressionQuality: 0.9) {
            _selectedPhotoData = State(initialValue: data)
        }
    }

    private var isEditingDraft: Bool { draft != nil }
    private var hasPhotoChanged: Bool { hasPickedNewPhoto || isPhotoRemoved }

    // A draft being edited compares against what it started with; a
    // brand new note counts any text or photo as unsaved.
    private var hasUnsavedChanges: Bool {
        if isEditingDraft {
            return text != originalText || hasPhotoChanged
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || selectedPhotoData != nil
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

                        Button("Remove Photo", role: .destructive) {
                            removePhoto()
                        }
                    }
                } header: {
                    SectionHeader("Photo")
                }

                // Sharing never applies to a draft, so the switch only
                // shows while composing a brand new note. Editing an
                // existing draft (whether it's re-saved as a draft or
                // posted from here) uses the "share new notes" setting
                // as is.
                if !isEditingDraft {
                    Section {
                        Toggle("Share with friends", isOn: $isSharedWithFriends)
                    } footer: {
                        Text("Everyone in your circle can read notes you share. This does not apply to drafts.")
                    }
                }

                if isEditingDraft {
                    Section {
                        Button("Delete Draft", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(isEditingDraft ? "Edit Draft" : "New Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { handleCancel() }
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
                guard let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
                selectedPhotoData = data
                hasPickedNewPhoto = true
                isPhotoRemoved = false
            }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                "Discard changes?",
                isPresented: $isShowingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) { dismiss() }
                Button("Keep Editing", role: .cancel) {}
            }
            .confirmationDialog(
                "Delete this draft?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { deleteDraft() }
                Button("Cancel", role: .cancel) {}
            }
        }
    }

    private func handleCancel() {
        if hasUnsavedChanges {
            isShowingDiscardConfirmation = true
        } else {
            dismiss()
        }
    }

    private func removePhoto() {
        selectedPhotoItem = nil
        selectedPhotoData = nil
        hasPickedNewPhoto = false
        isPhotoRemoved = true
    }

    private func save(asDraft: Bool) {
        var photoFileName = draft?.photoFileName

        if hasPhotoChanged {
            if let oldFileName = draft?.photoFileName {
                try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(oldFileName))
            }
            photoFileName = selectedPhotoData.flatMap { try? writePhotoToDisk($0) }
        }

        let note: Note
        if let draft {
            note = draft
            note.text = text
            note.photoFileName = photoFileName
        } else {
            note = Note.createDraft(in: context, text: text, photoFileName: photoFileName)
        }

        note.isDraft = asDraft

        if !asDraft {
            note.createdAt = Date()
            note.journal = Journal.journal(for: Date(), in: context)
        }

        if note.ownerUID == nil {
            note.ownerUID = Auth.auth().currentUser?.uid
        }
        // A draft is never shared, the security rules reject it.
        note.sharedWithFriends = asDraft ? false : isSharedWithFriends
        note.syncedAt = nil

        try? context.save()

        if !asDraft {
            NotificationScheduler.shared.cancelTodaysReminder()
            Task { await StreakSyncService.shared.sync(context: context) }
        }

        NoteSyncService.shared.upload(note)

        dismiss()
        if asDraft {
            DraftSaveBanner.shared.show()
        }
    }

    private func deleteDraft() {
        guard let draft else { return }
        if let fileName = draft.photoFileName {
            try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(fileName))
        }
        NoteSyncService.shared.delete(draft)
        context.delete(draft)
        try? context.save()
        dismiss()
    }

    private func writePhotoToDisk(_ data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        let url = FileManager.documentsDirectory.appendingPathComponent(fileName)
        try data.write(to: url)
        return fileName
    }
}

#Preview("New Note") {
    NoteComposerView()
        .modelContainer(PreviewContainer.shared)
}
