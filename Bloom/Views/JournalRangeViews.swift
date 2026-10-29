import SwiftUI

// A From and To day, both included.
struct JournalRange: Identifiable, Hashable {
    let from: Date
    let to: Date

    var id: String { "\(from.timeIntervalSince1970)-\(to.timeIntervalSince1970)" }
}

// The Date range sheet: From and To pickers, quick choices, and Show.
struct JournalRangePickerSheet: View {
    @ObservedObject var model: JournalModel
    let onShow: (JournalRange) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var from = Calendar.current.date(byAdding: .day, value: -29, to: Date()) ?? Date()
    @State private var to = Date()

    private var calendar: Calendar { .current }
    private var isValid: Bool { calendar.startOfDay(for: to) >= calendar.startOfDay(for: from) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Quick choices") {
                    Button("Last 7 days") { choose(daysBack: 6) }
                    Button("Last 30 days") { choose(daysBack: 29) }
                    Button("This year") {
                        from = calendar.dateInterval(of: .year, for: Date())?.start ?? Date()
                        to = Date()
                    }
                    Button("All time") {
                        from = model.index.earliestDay?.date() ?? Date()
                        to = Date()
                    }
                }

                Section {
                    DatePicker("From", selection: $from, displayedComponents: .date)
                    DatePicker("To", selection: $to, displayedComponents: .date)
                    if !isValid {
                        Label("The To date can\u{2019}t be earlier than the From date.", systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("Date range")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Show") {
                        let range = JournalRange(from: calendar.startOfDay(for: from), to: calendar.startOfDay(for: to))
                        dismiss()
                        onShow(range)
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func choose(daysBack: Int) {
        to = Date()
        from = calendar.date(byAdding: .day, value: -daysBack, to: Date()) ?? Date()
    }
}

// The notes in a range, grouped by month then day, with a count and Clear.
struct JournalRangeResultView: View {
    let range: JournalRange
    @ObservedObject var model: JournalModel

    @Environment(\.dismiss) private var dismiss

    private func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    var body: some View {
        let days = model.index.days(from: range.from, to: range.to, model.sortOrder)
        let count = model.index.noteCount(in: days)

        ScrollView {
            LazyVStack(alignment: .leading, spacing: 24, pinnedViews: .sectionHeaders) {
                Text("\(JournalFormat.noteCount(count)), \(dateText(range.from)) to \(dateText(range.to))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityAddTraits(.isHeader)

                ForEach(JournalGrouping.months(days)) { month in
                    Section {
                        ForEach(month.days) { day in
                            JournalDaySection(day: day, notes: model.index.notes(on: day, model.sortOrder))
                        }
                    } header: {
                        Text(JournalFormat.monthYear(month.key.date()))
                            .font(.title3)
                            .fontWeight(.bold)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 8)
                            .background(.regularMaterial)
                            .accessibilityAddTraits(.isHeader)
                    }
                }
            }
            .padding()
            .frame(maxWidth: 700, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .navigationTitle("Date range")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Clear") { dismiss() }
            }
        }
        .overlay {
            if days.isEmpty {
                ContentUnavailableView("Nothing in this range", systemImage: "calendar")
            }
        }
    }
}
