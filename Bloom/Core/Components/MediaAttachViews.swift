import SwiftUI
import SwiftData

// Today's posted notes that don't have a movie or show yet, for
// attaching one. A note has at most one entry.
struct MediaNotePickerList: View {
    let onPick: (Note) -> Void

    @Query(Note.todaysNotesDescriptor()) private var todaysNotes: [Note]

    private var available: [Note] {
        todaysNotes.filter { $0.mediaLogEntry == nil }
    }

    var body: some View {
        Group {
            if available.isEmpty {
                ContentUnavailableView(
                    "No notes to attach to",
                    systemImage: "doc.text",
                    description: Text("Notes you post today without a movie or show show up here.")
                )
            } else {
                List(available) { note in
                    Button {
                        onPick(note)
                    } label: {
                        Text(note.text.isEmpty ? "Untitled note" : note.text)
                            .lineLimit(3)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .frame(minHeight: 44)
                    }
                    .accessibilityHint("Attaches the movie or show to this note")
                }
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.background)
            }
        }
        .navigationTitle("Today's Notes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

enum MediaAttachChoice {
    case none
    case note(Note)
    case newNote
}

// After a review is written in the Library: leave it on its own,
// attach it to one of today's notes, or write a new note about it.
struct MediaAttachChoiceSheet: View {
    let draft: MediaReviewDraft
    let onChoose: (MediaAttachChoice) -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    HStack(spacing: Theme.Spacing.md) {
                        MediaPosterThumbnail(fileName: draft.posterFileName, path: draft.posterPath)
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            Text(draft.title)
                                .textStyle(.callout)
                                .fontWeight(.medium)
                            StarRatingView(rating: draft.rating)
                        }
                    }
                    .accessibilityElement(children: .combine)
                }

                Section {
                    Button("Don\u{2019}t attach to a note") { choose(.none) }
                        .frame(minHeight: 44)

                    NavigationLink("Attach to a note from today") {
                        MediaNotePickerList { note in choose(.note(note)) }
                    }
                    .frame(minHeight: 44)

                    Button("Write a new note about it") { choose(.newNote) }
                        .frame(minHeight: 44)
                } header: {
                    SectionHeader("What next?")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .navigationTitle("Save to Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    private func choose(_ choice: MediaAttachChoice) {
        onChoose(choice)
        dismiss()
    }
}
