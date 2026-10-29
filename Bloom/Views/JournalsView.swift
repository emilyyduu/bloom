import SwiftUI
import SwiftData

// Profile > Your Journals: the years that have at least one posted note,
// then (one tap in) that year's months, then a month's days. Drafts never
// appear. Years and months are only a way of grouping notes on screen, the
// Journal model and its Firestore backup stay grouped by day.
//
// This screen owns the notes query and the JournalModel every screen below
// it reads, so the counts are built once, in one pass, and rebuilt only
// when the notes change.
struct JournalsView: View {
    @Query(filter: #Predicate<Note> { !$0.isDraft }, sort: \Note.createdAt, order: .reverse)
    private var notes: [Note]

    @StateObject private var model = JournalModel()

    private var currentYear: Int { Calendar.current.component(.year, from: Date()) }

    var body: some View {
        List(model.index.years(model.sortOrder), id: \.self) { year in
            NavigationLink {
                JournalYearView(year: year, model: model)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(yearTitle(year))
                        .font(.headline)
                    Text(JournalFormat.noteCount(model.index.countByYear[year] ?? 0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle("Journals")
        .overlay {
            if notes.isEmpty {
                JournalsEmptyState()
            }
        }
        .journalTools(model)
        .onChange(of: notes, initial: true) { _, newNotes in
            model.update(notes: newNotes)
        }
    }

    private func yearTitle(_ year: Int) -> String {
        year == currentYear ? "\(JournalFormat.year(year)) so far" : JournalFormat.year(year)
    }
}

struct JournalsEmptyState: View {
    var body: some View {
        ContentUnavailableView(
            "No journals yet",
            systemImage: "book.closed",
            description: Text("Your journals will appear here once you\u{2019}ve logged a few notes.")
        )
    }
}

// MARK: - Year

// One year's months that have notes.
struct JournalYearView: View {
    let year: Int
    @ObservedObject var model: JournalModel

    var body: some View {
        List(model.index.months(in: year, model.sortOrder)) { month in
            NavigationLink {
                JournalMonthView(month: month, model: model)
            } label: {
                VStack(alignment: .leading, spacing: 4) {
                    Text(monthTitle(month))
                        .font(.headline)
                    Text(JournalFormat.noteCount(model.index.countByMonth[month] ?? 0))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .accessibilityElement(children: .combine)
            }
        }
        .navigationTitle(JournalFormat.year(year))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.index.months(in: year, model.sortOrder).isEmpty {
                JournalsEmptyState()
            }
        }
        .journalTools(model)
    }

    private func monthTitle(_ month: JournalMonthKey) -> String {
        let base = JournalFormat.monthYear(month.date())
        return month == JournalMonthKey(Date()) ? "\(base) so far" : base
    }
}

// MARK: - Month and day

// A month's notes under day headers.
struct JournalMonthView: View {
    let month: JournalMonthKey
    @ObservedObject var model: JournalModel

    var body: some View {
        let days = model.index.days(in: month, model.sortOrder)
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24) {
                ForEach(days) { day in
                    JournalDaySection(day: day, notes: model.index.notes(on: day, model.sortOrder))
                }
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(JournalFormat.monthYear(month.date()))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if days.isEmpty {
                JournalsEmptyState()
            }
        }
        .journalTools(model)
    }
}

// One day's notes, opened from the calendar.
struct JournalDayView: View {
    let day: JournalDayKey
    @ObservedObject var model: JournalModel

    var body: some View {
        let notes = model.index.notes(on: day, model.sortOrder)
        ScrollView {
            if !notes.isEmpty {
                JournalDaySection(day: day, notes: notes)
                    .padding()
                    .frame(maxWidth: 700, alignment: .leading)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle(JournalFormat.dayHeader(day.date()))
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if notes.isEmpty {
                ContentUnavailableView("Nothing on this day", systemImage: "calendar")
            }
        }
    }
}

// A day header and that day's note cards.
struct JournalDaySection: View {
    let day: JournalDayKey
    let notes: [Note]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(JournalFormat.dayHeader(day.date()))
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            ForEach(notes) { note in
                JournalNoteCard(note: note)
            }
        }
    }
}

// The note card every Journals screen uses.
struct JournalNoteCard: View {
    let note: Note

    @State private var detail: NoteDetailRequest?

    var body: some View {
        // A note deleted a moment ago, before the index catches up.
        if note.isDeleted || note.modelContext == nil {
            EmptyView()
        } else {
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(note.createdAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if note.isPinned {
                    PinIndicator()
                }
                Spacer()
                CommentBubbleButton(
                    ownerUID: note.ownerUID,
                    noteID: note.id.uuidString,
                    isEnabled: note.sharedWithFriends,
                    action: { detail = .mine(note, focusComments: true) }
                )
            }
            if !note.text.isEmpty {
                Text(note.text)
            }

            NoteVoiceMemo(note: note)

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
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { detail = .mine(note) }
        .sheet(item: $detail) { request in
            NoteDetailSheet(request: request)
        }
        .noteActions(note)
    }
}

// MARK: - Toolbar

// Sort, Calendar and Date range, on every Journals screen except the
// calendar itself.
private struct JournalTools: ViewModifier {
    @ObservedObject var model: JournalModel

    @State private var isShowingRangePicker = false
    @State private var range: JournalRange?

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItemGroup(placement: .primaryAction) {
                    Menu {
                        Picker("Sort", selection: $model.sortOrder) {
                            ForEach(JournalSortOrder.allCases) { order in
                                Text(order.title).tag(order)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                    }
                    .accessibilityLabel("Sort")
                    .accessibilityValue(model.sortOrder.title)

                    NavigationLink {
                        JournalCalendarView(model: model)
                    } label: {
                        Image(systemName: "calendar")
                    }
                    .accessibilityLabel("Calendar")

                    Button {
                        isShowingRangePicker = true
                    } label: {
                        Image(systemName: "calendar.badge.clock")
                    }
                    .accessibilityLabel("Date range")
                }
            }
            .sheet(isPresented: $isShowingRangePicker) {
                JournalRangePickerSheet(model: model) { chosen in
                    range = chosen
                }
            }
            .navigationDestination(item: $range) { chosen in
                JournalRangeResultView(range: chosen, model: model)
            }
    }
}

extension View {
    func journalTools(_ model: JournalModel) -> some View {
        modifier(JournalTools(model: model))
    }
}

#Preview {
    NavigationStack {
        JournalsView()
    }
    .modelContainer(PreviewContainer.shared)
}

#Preview("Dynamic Type - Accessibility 5") {
    NavigationStack {
        JournalsView()
    }
    .modelContainer(PreviewContainer.shared)
    .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Landscape", traits: .landscapeLeft) {
    NavigationStack {
        JournalsView()
    }
    .modelContainer(PreviewContainer.shared)
}
