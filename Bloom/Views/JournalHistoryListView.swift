import SwiftUI
import SwiftData

/// Every past day that has at least one note in it. There's no published
/// state to filter on, "past" just means not today.
struct JournalHistoryListView: View {
    @Query(sort: \Journal.date, order: .reverse) private var allJournals: [Journal]

    private var pastJournals: [Journal] {
        let startOfToday = Calendar.current.startOfDay(for: Date())
        return allJournals.filter { $0.date < startOfToday && !$0.sortedNotes.isEmpty }
    }

    var body: some View {
        NavigationStack {
            List(pastJournals) { journal in
                NavigationLink {
                    JournalDetailView(journal: journal)
                } label: {
                    VStack(alignment: .leading) {
                        Text(journal.date, style: .date)
                            .font(.headline)
                        let count = journal.sortedNotes.count
                        Text("\(count) note\(count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Your Journals")
            .overlay {
                if pastJournals.isEmpty {
                    ContentUnavailableView(
                        "No days yet",
                        systemImage: "book.closed",
                        description: Text("Your days will appear here once you've logged a few notes.")
                    )
                }
            }
        }
    }
}

private struct JournalDetailView: View {
    let journal: Journal

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(journal.sortedNotes) { note in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(note.createdAt, style: .time)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(note.text)

                        if let photo = note.photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle(journal.date.formatted(date: .abbreviated, time: .omitted))
    }
}

#Preview {
    JournalHistoryListView()
        .modelContainer(PreviewContainer.shared)
}
