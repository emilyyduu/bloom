import SwiftUI
import SwiftData
import FirebaseAuth

// Every note saved with "Save as Draft", newest first. Presented as a
// sheet from the Journal header's Drafts button, or nested inside
// NoteComposerView's own Drafts button.
//
// onSelect is nil by default: tapping a draft then opens it in a
// second composer sheet stacked on top of this one, which is what the
// Journal header and the composer's "Add" sheet still want. Passing a
// closure (as NoteComposerView does) replaces that with loading the
// draft straight into the caller instead.
struct DraftsView: View {
    var excludedDraft: Note?
    var onSelect: ((Note) -> Void)?

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Note> { $0.isDraft }, sort: \Note.createdAt, order: .reverse)
    private var allDrafts: [Note]

    @State private var draftToEdit: Note?
    @State private var draftPendingDeletion: Note?

    private var drafts: [Note] {
        guard let excludedDraft else { return allDrafts }
        return allDrafts.filter { $0.id != excludedDraft.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if drafts.isEmpty {
                    ContentUnavailableView(
                        "No drafts",
                        systemImage: "doc.text",
                        description: Text("Notes you save as drafts show up here.")
                    )
                } else {
                    List {
                        ForEach(drafts) { draft in
                            DraftRow(draft: draft)
                                .contentShape(Rectangle())
                                .onTapGesture { selectDraft(draft) }
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        draftPendingDeletion = draft
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                                .swipeActions(edge: .leading) {
                                    Button {
                                        addToToday(draft)
                                    } label: {
                                        Label("Add to Today", systemImage: "calendar.badge.plus")
                                    }
                                    .tint(Theme.Colors.actionFill)
                                }
                                .contextMenu {
                                    Button {
                                        selectDraft(draft)
                                    } label: {
                                        Label("Edit", systemImage: "pencil")
                                    }
                                    Button {
                                        addToToday(draft)
                                    } label: {
                                        Label("Add to Today", systemImage: "calendar.badge.plus")
                                    }
                                    Button(role: .destructive) {
                                        draftPendingDeletion = draft
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.Colors.background)
                    .listStyle(.plain)
                }
            }
            .navigationTitle("Drafts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $draftToEdit) { draft in
                NoteComposerView(draft: draft)
            }
            .alert(
                "Delete this draft?",
                isPresented: Binding(
                    get: { draftPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { draftPendingDeletion = nil }
                    }
                )
            ) {
                Button("Delete", role: .destructive) {
                    if let draftPendingDeletion { delete(draftPendingDeletion) }
                    draftPendingDeletion = nil
                }
                Button("Cancel", role: .cancel) {
                    draftPendingDeletion = nil
                }
            }
        }
    }

    private func selectDraft(_ draft: Note) {
        if let onSelect {
            onSelect(draft)
        } else {
            draftToEdit = draft
        }
    }

    // Matches what NoteComposerView does for "Add to Today": clear
    // isDraft, stamp createdAt to now so it lands in today's timeline
    // and counts toward today's streak, attach it to today's journal,
    // cancel today's reminder and re-sync the streak.
    private func addToToday(_ note: Note) {
        note.isDraft = false
        note.createdAt = Date()
        note.journal = Journal.journal(for: Date(), in: context)
        if note.ownerUID == nil {
            note.ownerUID = Auth.auth().currentUser?.uid
        }
        note.sharedWithFriends = AccountDefaults.shareNewNotes
        note.syncedAt = nil
        try? context.save()

        NotificationScheduler.shared.cancelTodaysReminder()
        Task { await StreakSyncService.shared.sync(context: context) }
        NoteSyncService.shared.upload(note)
    }

    private func delete(_ note: Note) {
        note.mediaLogEntry?.deleteCompletely(in: context)
        note.deleteAudioFile()
        if let fileName = note.photoFileName {
            try? FileManager.default.removeItem(at: FileManager.documentsDirectory.appendingPathComponent(fileName))
        }
        NoteSyncService.shared.delete(note)
        context.delete(note)
        try? context.save()
    }
}

private struct DraftRow: View {
    let draft: Note

    var body: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                if !draft.text.isEmpty || draft.audioSeconds == nil {
                    Text(draft.text)
                        .textStyle(.body)
                        .lineLimit(3)
                }
                if draft.hasAudio, let seconds = draft.audioSeconds {
                    Label(AudioPlayerView.format(TimeInterval(seconds)), systemImage: "mic")
                        .textStyle(.caption)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .accessibilityLabel("Voice memo, \(AudioPlayerView.format(TimeInterval(seconds)))")
                }
                Text("Saved \(relativeTime(draft.createdAt))")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let photo = draft.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                    .clipped()
            }
        }
        .padding(.vertical, 6)
    }
}

private func relativeTime(_ date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

#Preview {
    DraftsView()
        .modelContainer(PreviewContainer.shared)
}
