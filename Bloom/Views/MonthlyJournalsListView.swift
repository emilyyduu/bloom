import SwiftUI
import SwiftData

// Every month that has at least one non-draft note, newest first. The
// current month is always included, labelled "so far" since it isn't
// finished yet. Months are only a way of grouping notes on screen, the
// Journal model and its Firestore backup stay grouped by day.
struct MonthlyJournalsListView: View {
    @Query(filter: #Predicate<Note> { !$0.isDraft }, sort: \Note.createdAt, order: .reverse)
    private var notes: [Note]

    private var months: [MonthGroup] {
        let calendar = Calendar.current
        let currentMonthStart = calendar.dateInterval(of: .month, for: Date())?.start

        let grouped = Dictionary(grouping: notes) { note in
            calendar.dateInterval(of: .month, for: note.createdAt)?.start ?? note.createdAt
        }

        return grouped
            .map { monthStart, notes in
                MonthGroup(monthStart: monthStart, notes: notes, isCurrentMonth: monthStart == currentMonthStart)
            }
            .sorted { $0.monthStart > $1.monthStart }
    }

    var body: some View {
        List(months) { month in
            NavigationLink {
                MonthDetailView(month: month)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(month.title)
                        .font(.headline)
                    let count = month.notes.count
                    Text("\(count) note\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
            }
        }
        .navigationTitle("Monthly Journals")
        .overlay {
            if months.isEmpty {
                ContentUnavailableView(
                    "No journals yet",
                    systemImage: "book.closed",
                    description: Text("Your journals will appear here once you've logged a few notes.")
                )
            }
        }
    }
}

private struct MonthGroup: Identifiable {
    let monthStart: Date
    let notes: [Note]
    let isCurrentMonth: Bool

    var id: Date { monthStart }

    var title: String {
        let base = monthYearString(monthStart)
        return isCurrentMonth ? "\(base) so far" : base
    }
}

private struct DayGroup: Identifiable {
    let day: Date
    let notes: [Note]

    var id: Date { day }
}

private struct MonthDetailView: View {
    let month: MonthGroup

    private var dayGroups: [DayGroup] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: month.notes) { calendar.startOfDay(for: $0.createdAt) }
        return grouped
            .map { day, notes in
                DayGroup(day: day, notes: notes.sorted { $0.createdAt < $1.createdAt })
            }
            .sorted { $0.day < $1.day }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(dayGroups) { dayGroup in
                    VStack(alignment: .leading, spacing: 12) {
                        Text(dayHeaderString(dayGroup.day))
                            .font(.headline)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(dayGroup.notes) { note in
                            MonthlyJournalNoteRow(note: note)
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(month.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct MonthlyJournalNoteRow: View {
    let note: Note

    var body: some View {
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

            if let mediaLogEntry = note.mediaLogEntry {
                MediaLogChip(entry: mediaLogEntry)
            }
        }
    }
}

// Matches the locale-aware "dMMMM" pattern used elsewhere in the app
// (see HomeView's dateTitle), so day and month order follow the
// user's locale rather than being hard coded.
private func monthYearString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("yMMMM")
    return formatter.string(from: date)
}

private func dayHeaderString(_ date: Date) -> String {
    let weekdayFormatter = DateFormatter()
    weekdayFormatter.locale = .current
    weekdayFormatter.dateFormat = "EEEE"

    let dayMonthFormatter = DateFormatter()
    dayMonthFormatter.locale = .current
    dayMonthFormatter.setLocalizedDateFormatFromTemplate("dMMMM")

    return "\(weekdayFormatter.string(from: date)) \(dayMonthFormatter.string(from: date))"
}

#Preview {
    NavigationStack {
        MonthlyJournalsListView()
    }
    .modelContainer(PreviewContainer.shared)
}

#Preview("Dynamic Type - Accessibility 5") {
    NavigationStack {
        MonthlyJournalsListView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .accessibility5)
}
