import SwiftUI
import SwiftData

// Shown when tapping an entry in the Library or a note's movie card.
// Shows the full review, lets the person edit the rating and review,
// open the attached note, attach or detach, or delete the entry.
struct MediaLogEntryDetailView: View {
    let entry: MediaLogEntry

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingEdit = false
    @State private var isShowingAttach = false
    @State private var noteToView: Note?
    @State private var isShowingDeleteConfirmation = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: Theme.Spacing.md) {
                        posterImage
                            .frame(height: 220)
                            .frame(maxWidth: .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
                            .accessibilityHidden(true)

                        Text(entry.title)
                            .textStyle(.subheading)
                            .multilineTextAlignment(.center)

                        if let releaseYear = entry.releaseYear {
                            Text(String(releaseYear))
                                .textStyle(.callout)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }

                        StarRatingView(rating: entry.rating, font: .title3)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.sm)
                }

                Section {
                    if let review = entry.reviewText, !review.isEmpty {
                        Text(review)
                    } else {
                        Text("No review yet")
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    Button("Edit rating and review") { isShowingEdit = true }
                        .frame(minHeight: 44)
                } header: {
                    SectionHeader("Review")
                }

                Section {
                    if let note = entry.note {
                        Button {
                            noteToView = note
                        } label: {
                            Text(note.text.isEmpty ? "Untitled note" : note.text)
                                .lineLimit(3)
                                .foregroundStyle(Theme.Colors.textPrimary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityHint("Opens the note")

                        Button("Detach") { detach() }
                            .frame(minHeight: 44)
                    } else {
                        Button("Attach to a note") { isShowingAttach = true }
                            .frame(minHeight: 44)
                    }
                } header: {
                    SectionHeader("Attached note")
                }

                Section {
                    Button("Delete Entry", role: .destructive) {
                        isShowingDeleteConfirmation = true
                    }
                    .frame(minHeight: 44)
                }
            }
            .navigationTitle(entry.mediaType == "movie" ? "Movie" : "TV Show")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $isShowingEdit) {
                MediaReviewSheet(draft: MediaReviewDraft(entry: entry)) { edited in
                    entry.apply(edited)
                    try? context.save()
                }
            }
            .sheet(isPresented: $isShowingAttach) {
                NavigationStack {
                    MediaNotePickerList { note in
                        entry.note = note
                        try? context.save()
                        isShowingAttach = false
                    }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { isShowingAttach = false }
                        }
                    }
                }
            }
            .sheet(item: $noteToView) { note in
                NoteDetailSheet(note: note)
            }
            .confirmationDialog(
                "Delete this entry?",
                isPresented: $isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    entry.deleteCompletely(in: context)
                    try? context.save()
                    dismiss()
                }
            }
        }
    }

    private func detach() {
        entry.note = nil
        try? context.save()
    }

    @ViewBuilder
    private var posterImage: some View {
        if let image = entry.posterImage {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
        } else {
            Rectangle()
                .fill(Theme.Colors.surfaceMuted)
                .overlay {
                    Image(systemName: "film")
                        .textStyle(.display)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
        }
    }
}

#Preview {
    MediaLogEntryDetailView(entry: MediaLogEntry(
        tmdbID: 1,
        title: "Paddington",
        mediaType: "movie",
        releaseYear: 2014,
        posterFileName: nil,
        rating: 4
    ))
    .modelContainer(PreviewContainer.shared)
}
