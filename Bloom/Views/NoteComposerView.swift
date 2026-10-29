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

    // Both are @State, not just a stored let, because picking a
    // different draft from the nested Drafts sheet loads it into this
    // same composer instead of opening a second one.
    @State private var draft: Note?
    @State private var originalText: String

    @State private var text: String
    // Where the cursor is in the note, so a quick emoji lands there.
    @State private var textSelection: TextSelection?
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoData: Data?
    @State private var isSharedWithFriends: Bool
    @State private var hasPickedNewPhoto = false
    @State private var isPhotoRemoved = false
    @State private var isShowingDiscardConfirmation = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isShowingDraftsSheet = false
    @State private var pendingDraftSelection: Note?
    @State private var isShowingSaveDraftFirstDialog = false

    // The movie or show chosen for this note. It only becomes a stored
    // entry when the note is saved, so removing it first creates
    // nothing. originalMediaDraft is what the draft already had.
    @State private var mediaDraft: MediaReviewDraft?
    @State private var originalMediaDraft: MediaReviewDraft?
    @State private var isShowingMediaSearch = false
    @State private var isShowingMediaEdit = false

    // The voice memo for this note. Files recorded in this session that
    // aren't saved onto a note yet are tracked, so re-recording,
    // deleting or discarding never leaves a stray file, and an existing
    // draft's own file is never removed until the note is saved.
    @StateObject private var recorder = VoiceMemoRecorder()
    @State private var audioDraft: AudioDraft?
    @State private var originalAudio: AudioDraft?
    @State private var sessionAudioFiles: Set<String> = []

    private struct AudioDraft: Equatable {
        let fileName: String
        let seconds: Int
    }

    @Query(filter: #Predicate<Note> { $0.isDraft }) private var allDrafts: [Note]

    // Starts from the "Share new notes with friends" setting, so a
    // note only needs the switch flipped by hand when it should
    // differ from that default. Prefills text and photo when editing
    // an existing draft.
    init(editing note: Note) {
        self.init(draft: note)
    }

    init(draft: Note? = nil, attaching: MediaReviewDraft? = nil) {
        let existingMedia = draft?.mediaLogEntry.map(MediaReviewDraft.init(entry:))
        _mediaDraft = State(initialValue: attaching ?? existingMedia)
        _originalMediaDraft = State(initialValue: existingMedia)
        let existingAudio = Self.audioDraft(for: draft)
        _audioDraft = State(initialValue: existingAudio)
        _originalAudio = State(initialValue: existingAudio)
        let initialText = draft?.text ?? ""
        _draft = State(initialValue: draft)
        _originalText = State(initialValue: initialText)
        _text = State(initialValue: initialText)
        _isSharedWithFriends = State(initialValue: AccountDefaults.shareNewNotes)

        if let photo = draft?.photo, let data = photo.jpegData(compressionQuality: 0.9) {
            _selectedPhotoData = State(initialValue: data)
        }
    }

    private static func audioDraft(for note: Note?) -> AudioDraft? {
        guard let note, note.hasAudio, let fileName = note.audioFileName else { return nil }
        return AudioDraft(fileName: fileName, seconds: note.audioSeconds ?? 0)
    }

    // A voice memo alone is enough to save or post, text is optional.
    private var canSave: Bool {
        let hasText = !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return (hasText || audioDraft != nil) && !recorder.isRecording
    }

    // Editing a note that is already posted: same fields, but it can
    // never go back to being a draft, and its date, journal, sharing
    // and pin stay as they are.
    private var isEditingPosted: Bool { draft?.isDraft == false }

    private var isEditingDraft: Bool { draft != nil }
    private var hasPhotoChanged: Bool { hasPickedNewPhoto || isPhotoRemoved }

    // Excludes the draft currently open in this composer, since picking
    // it from its own Drafts list would be a no-op.
    private var availableDraftsCount: Int {
        allDrafts.filter { $0.id != draft?.id }.count
    }

    // A draft being edited compares against what it started with; a
    // brand new note counts any text or photo as unsaved.
    private var hasUnsavedChanges: Bool {
        if isEditingDraft {
            return text != originalText || hasPhotoChanged || mediaDraft != originalMediaDraft
                || audioDraft != originalAudio || recorder.isRecording
        }
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || selectedPhotoData != nil || mediaDraft != nil || audioDraft != nil || recorder.isRecording
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    quickEmojiRow
                        .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
                    TextEditor(text: $text, selection: $textSelection)
                        .frame(minHeight: 120)
                } header: {
                    SectionHeader("What's happening?")
                }

                voiceMemoSection

                Section {
                    if let mediaDraft {
                        MediaDraftCard(
                            draft: mediaDraft,
                            onEdit: { isShowingMediaEdit = true },
                            onRemove: { self.mediaDraft = nil }
                        )
                    } else {
                        Button {
                            isShowingMediaSearch = true
                        } label: {
                            Label("Log a movie or show", systemImage: "film")
                        }
                        .accessibilityHint("Search for a movie or show to add to this note")
                    }
                } header: {
                    SectionHeader("Movie or show")
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

                if isEditingDraft && !isEditingPosted {
                    Section {
                        Button("Delete Draft", role: .destructive) {
                            isShowingDeleteConfirmation = true
                        }
                    }
                }
            }
            .navigationTitle(isEditingPosted ? "Edit Note" : (isEditingDraft ? "Edit Draft" : "New Note"))
            // A posted note has no Drafts button or Save as Draft.
            .toolbar(isEditingPosted ? .hidden : .automatic, for: .bottomBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { handleCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isEditingPosted ? "Save" : "Add to Today") { save(asDraft: false) }
                        .disabled(!canSave)
                }
                ToolbarItem(placement: .bottomBar) {
                    HStack {
                        draftsButton
                        Spacer()
                        Button("Save as Draft") { save(asDraft: true) }
                            .disabled(!canSave)
                    }
                }
            }
            .task(id: selectedPhotoItem) {
                guard let selectedPhotoItem else { return }
                guard let data = try? await selectedPhotoItem.loadTransferable(type: Data.self) else { return }
                selectedPhotoData = data
                hasPickedNewPhoto = true
                isPhotoRemoved = false
            }
            .onChange(of: recorder.finished) { _, memo in
                if let memo { handleRecorded(memo) }
            }
            // Never leave a recording running or half finished behind.
            .onDisappear { recorder.stop(because: .discard) }
            .interactiveDismissDisabled(hasUnsavedChanges)
            .confirmationDialog(
                "Discard changes?",
                isPresented: $isShowingDiscardConfirmation,
                titleVisibility: .visible
            ) {
                Button("Discard", role: .destructive) {
                    discardSessionAudio()
                    dismiss()
                }
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
            .confirmationDialog(
                "Save this note as a draft first?",
                isPresented: $isShowingSaveDraftFirstDialog,
                titleVisibility: .visible
            ) {
                Button("Save Draft") {
                    persistCurrentNote(asDraft: true)
                    if let pendingDraftSelection {
                        loadDraft(pendingDraftSelection)
                    }
                }
                Button("Discard", role: .destructive) {
                    if let pendingDraftSelection {
                        loadDraft(pendingDraftSelection)
                    }
                }
                Button("Cancel", role: .cancel) {
                    pendingDraftSelection = nil
                }
            }
            .sheet(isPresented: $isShowingMediaSearch) {
                MediaSearchView { mediaDraft = $0 }
            }
            .sheet(isPresented: $isShowingMediaEdit) {
                if let mediaDraft {
                    MediaReviewSheet(draft: mediaDraft) { edited in
                        var updated = edited
                        updated.posterPath = mediaDraft.posterPath
                        updated.posterFileName = mediaDraft.posterFileName
                        self.mediaDraft = updated
                    }
                }
            }
            .sheet(isPresented: $isShowingDraftsSheet) {
                DraftsView(excludedDraft: draft) { selected in
                    isShowingDraftsSheet = false
                    handleDraftSelection(selected)
                }
            }
        }
    }

    // MARK: - Voice memo

    private var voiceMemoSection: some View {
        Section {
            if recorder.permission == .denied {
                VStack(spacing: 8) {
                    Text("Microphone access is off")
                        .font(.subheadline)
                        .fontWeight(.medium)
                    Text("Turn it on in Settings to record voice memos.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") { recorder.openSettings() }
                        .buttonStyle(.bordered)
                        .frame(minHeight: 44)
                }
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
            } else if recorder.isRecording {
                HStack {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                    Text("\(AudioPlayerView.format(recorder.elapsed)) of \(AudioPlayerView.format(TimeInterval(VoiceMemoRecorder.limitSeconds)))")
                        .monospacedDigit()
                        .accessibilityLabel("Recording, \(Int(recorder.elapsed)) seconds of \(VoiceMemoRecorder.limitSeconds)")
                    Spacer()
                    Button("Stop", systemImage: "stop.circle.fill") {
                        recorder.stop()
                    }
                    .buttonStyle(.borderless)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Stop recording")
                }
            } else if let audioDraft {
                AudioPlayerView(source: .local(FileManager.audioDirectory.appendingPathComponent(audioDraft.fileName)),
                                seconds: audioDraft.seconds)
                    .id(audioDraft.fileName)
                HStack(spacing: 16) {
                    Button("Re-record", systemImage: "mic") { startRecording() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("Re-record voice memo")
                    Button("Delete", systemImage: "trash", role: .destructive) { deleteAudio() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("Delete voice memo")
                }
                .buttonStyle(.borderless)
            } else {
                Button("Record", systemImage: "mic") { startRecording() }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Record voice memo")
                    .accessibilityHint("Records up to \(VoiceMemoRecorder.limitSeconds) seconds")
            }

            if let message = recorder.message {
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            SectionHeader("Voice memo")
        }
    }

    private func startRecording() {
        Task { await recorder.start() }
    }

    // A finished recording replaces whatever memo the note had.
    private func handleRecorded(_ memo: RecordedMemo) {
        if let old = audioDraft { removeIfSessionFile(old.fileName) }
        sessionAudioFiles.insert(memo.fileName)
        audioDraft = AudioDraft(fileName: memo.fileName, seconds: memo.seconds)
    }

    private func deleteAudio() {
        if let old = audioDraft { removeIfSessionFile(old.fileName) }
        audioDraft = nil
    }

    // Only files recorded in this session are removed right away.
    private func removeIfSessionFile(_ fileName: String) {
        guard sessionAudioFiles.remove(fileName) != nil else { return }
        try? FileManager.default.removeItem(at: FileManager.audioDirectory.appendingPathComponent(fileName))
    }

    private func discardSessionAudio() {
        for fileName in sessionAudioFiles {
            try? FileManager.default.removeItem(at: FileManager.audioDirectory.appendingPathComponent(fileName))
        }
        sessionAudioFiles = []
    }

    // Makes the note's memo match the composer. The old file goes, and
    // audioSyncedAt stays as it was when the memo was removed, so the
    // sync service deletes the old backup too.
    private func syncAudio(for note: Note) {
        let newName = audioDraft?.fileName
        if note.audioFileName != newName {
            note.deleteAudioFile()
            note.audioFileName = newName
            note.audioSeconds = audioDraft?.seconds
            if newName != nil { note.audioSyncedAt = nil }
        }
        if let newName { sessionAudioFiles.remove(newName) }
    }

    // A short scrolling row above the note text. Each button names its
    // emoji for VoiceOver and is at least 44 by 44 points.
    private var quickEmojiRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(Self.quickEmojis) { item in
                    Button {
                        insertEmoji(item.emoji)
                    } label: {
                        Text(item.emoji)
                            .font(.title2)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.name)
                }
            }
        }
    }

    private struct QuickEmoji: Identifiable {
        let emoji: String
        let name: String
        var id: String { name }
    }

    private static let quickEmojis: [QuickEmoji] = [
        QuickEmoji(emoji: "☀️", name: "Sun"),
        QuickEmoji(emoji: "☕️", name: "Coffee"),
        QuickEmoji(emoji: "🌧️", name: "Rain cloud"),
        QuickEmoji(emoji: "🍜", name: "Noodles"),
        QuickEmoji(emoji: "📚", name: "Books"),
        QuickEmoji(emoji: "🎬", name: "Clapper board"),
        QuickEmoji(emoji: "💛", name: "Yellow heart"),
        QuickEmoji(emoji: "😴", name: "Sleeping face"),
        QuickEmoji(emoji: "🌱", name: "Seedling"),
        QuickEmoji(emoji: "🎉", name: "Party popper"),
    ]

    // Inserts at the cursor, replacing any selected text, or at the end
    // if there is no cursor yet. Offsets are counted in whole
    // characters, so an emoji is never split.
    private func insertEmoji(_ emoji: String) {
        var lower = text.endIndex
        var upper = text.endIndex
        if let textSelection, case .selection(let range) = textSelection.indices,
           range.upperBound <= text.endIndex {
            lower = range.lowerBound
            upper = range.upperBound
        }
        let insertOffset = text.distance(from: text.startIndex, to: lower)

        text.replaceSubrange(lower..<upper, with: emoji)

        let cursor = text.index(text.startIndex, offsetBy: insertOffset + 1, limitedBy: text.endIndex) ?? text.endIndex
        textSelection = TextSelection(insertionPoint: cursor)
    }

    // Visible even at zero drafts, so it's always findable; the count
    // badge is an addition, not the only way to tell drafts exist.
    private var draftsButton: some View {
        Button {
            isShowingDraftsSheet = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "doc.text")
                if availableDraftsCount > 0 {
                    Text("\(availableDraftsCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.red))
                        .offset(x: 10, y: -10)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Drafts")
        .accessibilityValue("\(availableDraftsCount) draft\(availableDraftsCount == 1 ? "" : "s")")
    }

    // Picking a draft while the current note has unsaved changes asks
    // first, since loading the new draft overwrites what's on screen.
    private func handleDraftSelection(_ selected: Note) {
        if hasUnsavedChanges {
            pendingDraftSelection = selected
            isShowingSaveDraftFirstDialog = true
        } else {
            loadDraft(selected)
        }
    }

    private func loadDraft(_ newDraft: Note) {
        draft = newDraft
        originalText = newDraft.text
        text = newDraft.text
        let existingMedia = newDraft.mediaLogEntry.map(MediaReviewDraft.init(entry:))
        mediaDraft = existingMedia
        originalMediaDraft = existingMedia
        discardSessionAudio()
        let existingAudio = Self.audioDraft(for: newDraft)
        audioDraft = existingAudio
        originalAudio = existingAudio
        selectedPhotoItem = nil
        hasPickedNewPhoto = false
        isPhotoRemoved = false
        if let photo = newDraft.photo, let data = photo.jpegData(compressionQuality: 0.9) {
            selectedPhotoData = data
        } else {
            selectedPhotoData = nil
        }
        pendingDraftSelection = nil
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

    @discardableResult
    private func persistCurrentNote(asDraft: Bool) -> Note {
        var photoFileName = draft?.photoFileName

        if hasPhotoChanged {
            if let oldFileName = draft?.photoFileName {
                try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(oldFileName))
            }
            photoFileName = selectedPhotoData.flatMap { try? FileManager.writePhotoData($0) }
        }

        let wasPosted = isEditingPosted
        let note: Note
        if let draft {
            note = draft
            note.text = text
            note.photoFileName = photoFileName
            // A replaced photo is uploaded again over the old one, a
            // removed photo has its backup deleted. Either way the
            // sync service has to see the photo as not yet synced.
            if hasPhotoChanged { note.photoSyncedAt = nil }
        } else {
            note = Note.createDraft(in: context, text: text, photoFileName: photoFileName)
        }

        note.isDraft = asDraft
        syncMediaEntry(for: note)
        syncAudio(for: note)

        if !asDraft && !wasPosted {
            note.createdAt = Date()
            note.journal = Journal.journal(for: Date(), in: context)
        }

        if note.ownerUID == nil {
            note.ownerUID = Auth.auth().currentUser?.uid
        }
        // A draft is never shared, the security rules reject it. A
        // note that is already posted keeps whatever sharing it has.
        if !wasPosted {
            note.sharedWithFriends = asDraft ? false : isSharedWithFriends
        }
        // The upload stamps updatedAt on the note document.
        note.syncedAt = nil

        try? context.save()

        // An edit changes neither streaks nor reminders.
        if !asDraft && !wasPosted {
            NotificationScheduler.shared.cancelTodaysReminder()
            Task { await StreakSyncService.shared.sync(context: context) }
        }

        NoteSyncService.shared.upload(note)
        return note
    }

    // Creates, updates or removes the note's movie or show to match what
    // the composer shows. A note has at most one entry.
    private func syncMediaEntry(for note: Note) {
        let existing = note.mediaLogEntry
        guard let mediaDraft else {
            existing?.deleteCompletely(in: context)
            return
        }
        if let existing, existing.tmdbID == mediaDraft.tmdbID {
            existing.apply(mediaDraft)
        } else {
            existing?.deleteCompletely(in: context)
            _ = MediaLogEntry.create(from: mediaDraft, note: note, in: context)
        }
    }

    private func save(asDraft: Bool) {
        persistCurrentNote(asDraft: asDraft)
        dismiss()
        if asDraft {
            DraftSaveBanner.shared.show()
        }
    }

    private func deleteDraft() {
        guard let draft else { return }
        NoteSyncService.shared.delete(draft)
        draft.mediaLogEntry?.deleteCompletely(in: context)
        draft.deleteAudioFile()
        discardSessionAudio()
        if let fileName = draft.photoFileName {
            try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(fileName))
        }
        context.delete(draft)
        try? context.save()
        dismiss()
    }
}

#Preview("New Note") {
    NoteComposerView()
        .modelContainer(PreviewContainer.shared)
}

#Preview("Dark") {
    NoteComposerView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}

#Preview("Accessibility 5") {
    NoteComposerView()
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Landscape", traits: .landscapeLeft) {
    NoteComposerView()
        .modelContainer(PreviewContainer.shared)
}
