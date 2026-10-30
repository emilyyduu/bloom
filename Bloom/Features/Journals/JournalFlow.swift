import SwiftUI

// The journal flow, for my own journals only (friends see just today's
// notes, see FriendTodayView): years, then a year's months, then a month's
// calendar, then a day's chain. Every level is pushed onto the one
// NavigationStack that already holds the screen, so each has a back button.
// The links use destination closures, not values, because the Profile stack
// is bound to a typed path that can't hold journal values. The screens only
// know a JournalIndex and a JournalSource.

// How a note opens in the detail sheet, and the card a note shows on the
// day's chain.
struct JournalSource<Item: JournalItem, Card: View> {
    let request: (Item, _ focusComments: Bool) -> NoteDetailRequest
    let card: (Item, _ onComment: @escaping () -> Void, _ onTap: @escaping () -> Void) -> Card

    init(
        request: @escaping (Item, Bool) -> NoteDetailRequest,
        @ViewBuilder card: @escaping (Item, @escaping () -> Void, @escaping () -> Void) -> Card
    ) {
        self.request = request
        self.card = card
    }
}

// MARK: - Years

// The first level: a shelf of year books, newest first, each with its note
// count. My books can have a photo cover.
struct JournalYearsScreen<Item: JournalItem, Card: View>: View {
    let title: String
    @ObservedObject var model: JournalModel<Item>
    let source: JournalSource<Item, Card>
    var footnote: String?

    @ObservedObject private var covers = JournalCoverStore.shared
    @StateObject private var editor = JournalCoverEditor()
    @State private var editingYear: CoverYear?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                JournalShelf(header: "Years", minimumBookWidth: 150) {
                    ForEach(model.index.years, id: \.self) { year in
                        let key = JournalCoverStore.yearKey(year)
                        JournalBook(
                            title: JournalFormat.year(year),
                            spokenName: "\(JournalFormat.year(year)) journal",
                            count: model.index.count(in: year),
                            accent: covers.accent(for: key, automaticIndex: year),
                            coverImage: covers.image(for: key),
                            hint: "Opens the year"
                        ) {
                            JournalYearScreen(year: year, model: model, source: source)
                        }
                        .journalCoverMenu(key: key, canEdit: true, editor: editor, covers: covers) {
                            editingYear = CoverYear(id: year)
                        }
                    }
                }

                if let footnote {
                    Text(footnote)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if model.index.isEmpty {
                ContentUnavailableView(
                    "No journals yet",
                    systemImage: "book.closed",
                    description: Text("Your journals will appear here once you\u{2019}ve logged a few notes.")
                )
            }
        }
        .journalCoverEditing(editor)
        .sheet(item: $editingYear) { target in
            JournalCoverSheet(
                key: JournalCoverStore.yearKey(target.id),
                title: JournalFormat.year(target.id),
                subtitle: JournalFormat.noteCount(model.index.count(in: target.id)),
                automaticIndex: target.id
            )
        }
    }
}

private struct CoverYear: Identifiable {
    let id: Int
}

// MARK: - Year

// One year's months that have notes, as books, newest first.
struct JournalYearScreen<Item: JournalItem, Card: View>: View {
    let year: Int
    @ObservedObject var model: JournalModel<Item>
    let source: JournalSource<Item, Card>

    @ObservedObject private var covers = JournalCoverStore.shared
    @StateObject private var editor = JournalCoverEditor()
    @State private var isEditingCover = false
    @State private var editingMonth: JournalMonthKey?

    var body: some View {
        let months = model.index.months(in: year)
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                JournalShelf(header: "Months", minimumBookWidth: 100) {
                    ForEach(months) { month in
                        let key = JournalCoverStore.monthKey(month)
                        JournalBook(
                            title: JournalFormat.monthOnly(month.date()),
                            spokenName: "\(JournalFormat.monthYear(month.date())) journal",
                            count: model.index.count(in: month),
                            accent: covers.accent(for: key, automaticIndex: month.year * 12 + month.month),
                            coverImage: covers.image(for: key),
                            isCompact: true,
                            hint: "Opens the month"
                        ) {
                            JournalMonthScreen(month: month, model: model, source: source)
                        }
                        .journalCoverMenu(key: key, canEdit: true, editor: editor, covers: covers) {
                            editingMonth = month
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(JournalFormat.year(year))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit cover") { isEditingCover = true }
            }
        }
        .overlay {
            if months.isEmpty {
                ContentUnavailableView("Nothing in \(JournalFormat.year(year))", systemImage: "calendar")
            }
        }
        .journalCoverEditing(editor)
        .sheet(isPresented: $isEditingCover) {
            JournalCoverSheet(
                key: JournalCoverStore.yearKey(year),
                title: JournalFormat.year(year),
                subtitle: JournalFormat.noteCount(model.index.count(in: year)),
                automaticIndex: year
            )
        }
        .sheet(item: $editingMonth) { month in
            JournalCoverSheet(
                key: JournalCoverStore.monthKey(month),
                title: JournalFormat.monthOnly(month.date()),
                subtitle: JournalFormat.noteCount(model.index.count(in: month)),
                automaticIndex: month.year * 12 + month.month,
                isCompact: true
            )
        }
    }
}

// MARK: - Month (calendar)

// A month as a calendar. The previous and next buttons move through any
// month, including ones with no notes, which show an empty calendar. At
// accessibility text sizes seven columns can't stay legible, so the grid
// becomes a list of just the days that have notes.
struct JournalMonthScreen<Item: JournalItem, Card: View>: View {
    @ObservedObject var model: JournalModel<Item>
    let source: JournalSource<Item, Card>

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var month: JournalMonthKey
    @State private var isEditingCover = false

    init(month: JournalMonthKey, model: JournalModel<Item>, source: JournalSource<Item, Card>) {
        _month = State(initialValue: month)
        self.model = model
        self.source = source
    }

    private var calendar: Calendar { model.index.calendar }

    var body: some View {
        let noteCount = model.index.count(in: month)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                monthControls

                Text(noteCount == 0
                     ? "No notes this month"
                     : JournalFormat.summary(notes: noteCount, days: model.index.dayCount(in: month)))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)

                if dynamicTypeSize.isAccessibilitySize {
                    dayList
                } else {
                    JournalCalendarGrid(month: month, index: model.index) { day in
                        JournalDayScreen(day: day, model: model, source: source)
                    }
                    JournalCalendarLegend()
                }
            }
            .padding()
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        // The month and year are already the header between the arrows, so
        // the bar only carries the back button.
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit cover") { isEditingCover = true }
            }
        }
        .sheet(isPresented: $isEditingCover) {
            JournalCoverSheet(
                key: JournalCoverStore.monthKey(month),
                title: JournalFormat.monthOnly(month.date()),
                subtitle: JournalFormat.noteCount(model.index.count(in: month)),
                automaticIndex: month.year * 12 + month.month,
                isCompact: true
            )
        }
    }

    private var monthControls: some View {
        HStack {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Previous month")

            Spacer()

            Text(JournalFormat.monthYear(month.date()))
                .font(.title3)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .accessibilityAddTraits(.isHeader)

            Spacer()

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Next month")
        }
    }

    private func step(_ delta: Int) {
        guard let moved = calendar.date(byAdding: .month, value: delta, to: month.date(calendar: calendar)) else { return }
        month = JournalMonthKey(moved, calendar: calendar)
    }

    private var dayList: some View {
        VStack(alignment: .leading, spacing: 12) {
            ForEach(model.index.days(in: month)) { day in
                NavigationLink {
                    JournalDayScreen(day: day, model: model, source: source)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(JournalFormat.dayHeader(day.date(calendar: calendar)))
                            .font(.headline)
                        Text(JournalFormat.noteCount(model.index.count(on: day)))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// How strongly a day is shaded by its number of notes: none, 1, 2 to 3,
// 4 or more.
private enum JournalShade {
    static func opacity(for count: Int) -> Double {
        switch count {
        case 0: return 0
        case 1: return 0.18
        case 2...3: return 0.4
        default: return 0.65
        }
    }

    static func color(for count: Int) -> Color {
        Theme.Colors.blooming.opacity(opacity(for: count))
    }
}

private struct JournalCalendarGrid<Item: JournalItem, Destination: View>: View {
    let month: JournalMonthKey
    let index: JournalIndex<Item>
    @ViewBuilder let destination: (JournalDayKey) -> Destination

    private var calendar: Calendar { index.calendar }
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    // Weekday initials starting at the locale's first weekday.
    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    // Blanks before the 1st, then the month's day numbers.
    private var cells: [Int?] {
        let first = month.date(calendar: calendar)
        let weekday = calendar.component(.weekday, from: first)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        return Array(repeating: nil, count: blanks) + (1...count).map { Optional($0) }
    }

    var body: some View {
        let today = JournalDayKey(Date(), calendar: calendar)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            ForEach(Array(cells.enumerated()), id: \.offset) { _, number in
                if let number {
                    let day = JournalDayKey(year: month.year, month: month.month, day: number)
                    JournalDayCell(day: day, count: index.count(on: day), isToday: day == today, calendar: calendar) {
                        destination(day)
                    }
                } else {
                    Color.clear
                        .accessibilityHidden(true)
                }
            }
        }
    }
}

// One day of the grid: its number, a shade and a small count when it has
// notes, a ring when it is today. VoiceOver reads "14 October, 3 notes".
// A day without notes is disabled.
private struct JournalDayCell<Destination: View>: View {
    let day: JournalDayKey
    let count: Int
    let isToday: Bool
    let calendar: Calendar
    @ViewBuilder let destination: () -> Destination

    @ScaledMetric(relativeTo: .body) private var minHeight: CGFloat = 52

    private var label: String {
        let base = JournalFormat.dayMonth(day.date(calendar: calendar))
        let notes = count == 0 ? "no notes" : JournalFormat.noteCount(count)
        return "\(base), \(notes)" + (isToday ? ", today" : "")
    }

    private var content: some View {
        VStack(spacing: 2) {
            Text("\(day.day)")
                .font(.body)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundStyle(count > 0 ? Color.primary : Color.secondary)
            // Keeps every cell the same height whether or not it has a count.
            Text(count > 0 ? "\(count)" : " ")
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .background(JournalShade.color(for: count), in: RoundedRectangle(cornerRadius: 10))
        .overlay {
            if isToday {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    var body: some View {
        if count > 0 {
            NavigationLink {
                destination()
            } label: {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        } else {
            Button {} label: {
                content
            }
            .buttonStyle(.plain)
            .disabled(true)
            .accessibilityLabel(label)
        }
    }
}

// Explains the shades, and the ring for today.
private struct JournalCalendarLegend: View {
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { items }
            VStack(alignment: .leading, spacing: 8) { items }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        // The shade and count already say this on each day.
        .accessibilityHidden(true)
    }

    @ViewBuilder private var items: some View {
        swatch(count: 1, text: "1 note")
        swatch(count: 2, text: "2 to 3")
        swatch(count: 4, text: "4 or more")
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: 16, height: 16)
            Text("Today")
        }
    }

    private func swatch(count: Int, text: String) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 4)
                .fill(JournalShade.color(for: count))
                .frame(width: 16, height: 16)
            Text(text)
        }
    }
}

// MARK: - Day (chain)

// One day as the same chain Home shows: time, dot and line on the left and
// a card for each note. The arrows jump to the nearest day with notes
// before or after, without leaving the screen.
struct JournalDayScreen<Item: JournalItem, Card: View>: View {
    @ObservedObject var model: JournalModel<Item>
    let source: JournalSource<Item, Card>

    @State private var day: JournalDayKey
    @State private var detail: NoteDetailRequest?

    init(day: JournalDayKey, model: JournalModel<Item>, source: JournalSource<Item, Card>) {
        _day = State(initialValue: day)
        self.model = model
        self.source = source
    }

    var body: some View {
        let items = model.index.items(on: day)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header(count: items.count)

                if items.isEmpty {
                    ContentUnavailableView("No notes on this day", systemImage: "calendar")
                } else {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { position, item in
                            TimelineRow(date: item.createdAt, isLast: position == items.count - 1) {
                                source.card(
                                    item,
                                    { detail = source.request(item, true) },
                                    { detail = source.request(item, false) }
                                )
                            }
                        }
                    }
                }
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle(JournalFormat.dayHeader(day.date(calendar: model.index.calendar)))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $detail) { request in
            NoteDetailSheet(request: request)
        }
    }

    private func header(count: Int) -> some View {
        let previous = model.index.day(before: day)
        let next = model.index.day(after: day)
        return HStack {
            Button {
                if let previous { day = previous }
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(previous == nil)
            .accessibilityLabel("Previous day with notes")

            Spacer()

            VStack(spacing: 2) {
                Text(JournalFormat.dayHeader(day.date(calendar: model.index.calendar)))
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .accessibilityAddTraits(.isHeader)
                Text(JournalFormat.noteCount(count))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                if let next { day = next }
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(next == nil)
            .accessibilityLabel("Next day with notes")
        }
    }
}
