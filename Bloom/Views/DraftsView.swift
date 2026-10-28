import SwiftUI
import SwiftData
import FirebaseAuth

// Every note saved with "Save as Draft", newest first. Presented as a
// sheet from the Journal header's Drafts button.
struct DraftsView: View {
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss

    @Query(filter: #Predicate<Note> { $0.isDraft }, sort: \Note.createdAt, order: .reverse)
    private var drafts: [Note]

    @State private var draftToEdit: Note?
    @State private var draftPendingDeletion: Note?

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
                                .onTapGesture { draftToEdit = draft }
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
                                    .tint(.accentColor)
                                }
                                .contextMenu {
                                    Button {
                                        draftToEdit = draft
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
            .confirmationDialog(
                "Delete this draft?",
                isPresented: Binding(
                    get: { draftPendingDeletion != nil },
                    set: { isPresented in
                        if !isPresented { draftPendingDeletion = nil }
                    }
                ),
                titleVisibility: .visible
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
        note.sharedWithFriends = UserDefaults.standard.bool(forKey: "shareNewNotesWithFriends")
        note.syncedAt = nil
        try? context.save()

        NotificationScheduler.shared.cancelTodaysReminder()
        Task { await StreakSyncService.shared.sync(context: context) }
        NoteSyncService.shared.upload(note)
    }

    private func delete(_ note: Note) {
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
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(draft.text)
                    .font(.body)
                    .lineLimit(3)
                Text("Saved \(relativeTime(draft.createdAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if let photo = draft.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
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
