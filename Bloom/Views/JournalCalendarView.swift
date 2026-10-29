import SwiftUI

// A month grid with a dot on every day that has notes. Tapping a day opens
// that day's notes. At accessibility text sizes the grid becomes a list of
// the month's days that have notes, since seven columns can't stay legible.
struct JournalCalendarView: View {
    @ObservedObject var model: JournalModel

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var month = JournalMonthKey(Date())
    @State private var selectedDay: JournalDayKey?
    @State private var isPickingMonth = false

    private var calendar: Calendar { .current }
    private var thisMonth: JournalMonthKey { JournalMonthKey(Date()) }

    // The earliest year offered: the first note's, never later than this year.
    private var firstYear: Int {
        min(model.index.earliestDay?.year ?? thisMonth.year, thisMonth.year)
    }
    private var canGoBack: Bool { month > JournalMonthKey(year: firstYear, month: 1) }
    private var canGoForward: Bool { month < thisMonth }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                monthControls
                if dynamicTypeSize.isAccessibilitySize {
                    dayList
                } else {
                    grid
                }
            }
            .padding()
            .frame(maxWidth: 600)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Calendar")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $selectedDay) { day in
            JournalDayView(day: day, model: model)
        }
        .sheet(isPresented: $isPickingMonth) {
            MonthYearPicker(month: $month, firstYear: firstYear, lastMonth: thisMonth)
        }
    }

    // MARK: Month controls

    private var monthControls: some View {
        HStack {
            Button {
                step(-1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canGoBack)
            .accessibilityLabel("Previous month")

            Spacer()

            Button {
                isPickingMonth = true
            } label: {
                HStack(spacing: 4) {
                    Text(JournalFormat.monthYear(month.date()))
                        .font(.headline)
                    Image(systemName: "chevron.down")
                        .font(.caption)
                }
                .frame(minHeight: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(JournalFormat.monthYear(month.date())), choose month and year")

            Spacer()

            Button {
                step(1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .disabled(!canGoForward)
            .accessibilityLabel("Next month")
        }
    }

    private func step(_ delta: Int) {
        guard let moved = calendar.date(byAdding: .month, value: delta, to: month.date()) else { return }
        month = JournalMonthKey(moved)
    }

    // MARK: Grid

    private var columns: [GridItem] { Array(repeating: GridItem(.flexible(), spacing: 4), count: 7) }

    // Weekday initials starting at the locale's first weekday.
    private var weekdayHeaders: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let start = calendar.firstWeekday - 1
        return Array(symbols[start...] + symbols[..<start])
    }

    // Blanks before the 1st, then the month's day numbers.
    private var cells: [Int?] {
        let first = month.date()
        let weekday = calendar.component(.weekday, from: first)
        let blanks = (weekday - calendar.firstWeekday + 7) % 7
        let count = calendar.range(of: .day, in: .month, for: first)?.count ?? 30
        return Array(repeating: nil, count: blanks) + (1...count).map { Optional($0) }
    }

    private var grid: some View {
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(Array(weekdayHeaders.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }

            ForEach(Array(cells.enumerated()), id: \.offset) { _, day in
                if let day {
                    DayCell(
                        day: JournalDayKey(year: month.year, month: month.month, day: day),
                        count: model.index.count(on: JournalDayKey(year: month.year, month: month.month, day: day)),
                        isToday: JournalDayKey(Date()) == JournalDayKey(year: month.year, month: month.month, day: day),
                        isFuture: JournalDayKey(year: month.year, month: month.month, day: day) > JournalDayKey(Date())
                    ) {
                        selectedDay = JournalDayKey(year: month.year, month: month.month, day: day)
                    }
                } else {
                    Color.clear.frame(minHeight: 44)
                        .accessibilityHidden(true)
                }
            }
        }
    }

    // MARK: Accessibility sizes

    private var dayList: some View {
        let days = model.index.days(in: month, model.sortOrder)
        return VStack(alignment: .leading, spacing: 12) {
            if days.isEmpty {
                ContentUnavailableView("Nothing this month", systemImage: "calendar")
            }
            ForEach(days) { day in
                Button {
                    selectedDay = day
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(JournalFormat.dayHeader(day.date()))
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

// One day of the grid. The number, a ring if it is today and a dot if it
// has notes. VoiceOver reads "14 October, 3 notes".
private struct DayCell: View {
    let day: JournalDayKey
    let count: Int
    let isToday: Bool
    let isFuture: Bool
    let action: () -> Void

    private var label: String {
        let base = JournalFormat.dayMonth(day.date())
        let notes = count == 0 ? "no notes" : JournalFormat.noteCount(count)
        return "\(base), \(notes)" + (isToday ? ", today" : "")
    }

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text("\(day.day)")
                    .font(.body)
                    .fontWeight(isToday ? .bold : .regular)
                    .foregroundStyle(isFuture ? Color.secondary : Color.primary)
                Circle()
                    .fill(count > 0 ? Color.accentColor : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .overlay {
                if isToday {
                    RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isToday ? .isSelected : [])
    }
}

// Pick a month and a year by hand.
private struct MonthYearPicker: View {
    @Binding var month: JournalMonthKey
    let firstYear: Int
    let lastMonth: JournalMonthKey

    @Environment(\.dismiss) private var dismiss
    @State private var year: Int
    @State private var monthNumber: Int

    init(month: Binding<JournalMonthKey>, firstYear: Int, lastMonth: JournalMonthKey) {
        _month = month
        self.firstYear = firstYear
        self.lastMonth = lastMonth
        _year = State(initialValue: month.wrappedValue.year)
        _monthNumber = State(initialValue: month.wrappedValue.month)
    }

    private var monthNames: [String] { Calendar.current.monthSymbols }

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $monthNumber) {
                    ForEach(1...12, id: \.self) { number in
                        Text(monthNames[number - 1]).tag(number)
                    }
                }
                .pickerStyle(.wheel)

                Picker("Year", selection: $year) {
                    ForEach(firstYear...lastMonth.year, id: \.self) { value in
                        Text(JournalFormat.year(value)).tag(value)
                    }
                }
                .pickerStyle(.wheel)
            }
            .navigationTitle("Choose month")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        // The newest month is this month, never a future one.
                        month = min(JournalMonthKey(year: year, month: monthNumber), lastMonth)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
