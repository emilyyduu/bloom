#if DEBUG
import Foundation
import SwiftData

// DEBUG only: about 60 posted notes spread over 2024, 2025 and 2026 so the
// Journals screens (years, months, calendar, date range) have something to
// show. Every text starts with Note.samplePrefix, which is how the notes
// are found again. They are marked as already backed up (syncedAt) and
// Note.isSample keeps them out of uploads, sharing and pins, so they never
// reach Firestore. Real notes are never touched.
@MainActor
enum SampleJournalHistory {
    private static let lines = [
        "Slow morning, coffee on the balcony.",
        "Finished the reading for FIT3178 and started the assignment.",
        "Rainy walk to campus, forgot my umbrella again.",
        "Cooked dumplings with Mum, the kitchen smelled amazing.",
        "Long catch up call with an old friend.",
        "Tried a new cafe near the station, the toast was great.",
        "Gym session felt good, new personal best.",
        "Could not focus today, took a break and drew for an hour.",
        "Group meeting went better than expected.",
        "Watched the sunset from the tram.",
        "Bought a plant for my desk and named it Basil.",
        "Early start, quiet library, got loads done.",
        "Birthday dinner for Priya, so much laughing.",
        "Cleaned my room and found my old notebooks.",
        "A short run by the river, legs are sore.",
        "Movie night with the housemates.",
        "Bad sleep, but a good lunch fixed the mood.",
        "Handed in the report with ten minutes to spare.",
        "Spent the afternoon reading in the park.",
        "Markets on Saturday, picked up fresh bread and flowers.",
        "Felt grateful for small things today.",
        "Baked banana bread, burnt the edges a bit.",
        "Went to a gig with Tom, my ears are still ringing.",
        "Rest day. Did nothing and it was perfect.",
        "Planned the trip for next month on a big map.",
        "Learned a new chord on the guitar.",
        "Walked the long way home just to think.",
        "Exam done. Pizza to celebrate.",
        "Wrote a long letter I might never send.",
        "Windy day, the whole street smelled like jasmine.",
    ]

    // About 60 notes, spread evenly from the start of 2024 until now, with
    // a second note on a few days. Running it again replaces the old ones.
    @discardableResult
    static func add(to context: ModelContext) -> Int {
        remove(from: context)

        let calendar = Calendar.current
        let now = Date()
        guard let start = calendar.date(from: DateComponents(year: 2024, month: 1, day: 3)) else { return 0 }
        let totalDays = max(calendar.dateComponents([.day], from: start, to: now).day ?? 1, 1)

        let baseCount = 52
        var created = 0
        for index in 0..<baseCount {
            let dayOffset = min(index * totalDays / baseCount + (index * 7) % 9, totalDays)
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: start) else { continue }

            // Every seventh day gets a morning and an evening note.
            let hours = index % 7 == 0 ? [9, 21] : [8 + (index * 5) % 13]
            for (position, hour) in hours.enumerated() {
                guard let when = calendar.date(bySettingHour: hour, minute: (index * 13 + position * 7) % 60, second: 0, of: day),
                      when <= now else { continue }
                insert(text: lines[(index + position * 11) % lines.count], at: when, in: context)
                created += 1
            }
        }
        try? context.save()
        return created
    }

    // Deletes only notes whose text starts with "Sample: ". They were never
    // uploaded, so no cloud copy or pending deletion is involved.
    @discardableResult
    static func remove(from context: ModelContext) -> Int {
        let all = (try? context.fetch(FetchDescriptor<Note>())) ?? []
        let samples = all.filter { $0.text.hasPrefix(Note.samplePrefix) }
        for note in samples { context.delete(note) }
        try? context.save()
        return samples.count
    }

    private static func insert(text: String, at date: Date, in context: ModelContext) {
        let note = Note(text: Note.samplePrefix + text)
        note.isDraft = false
        note.createdAt = date
        // Marked as backed up so syncPending never picks it up.
        note.syncedAt = Date()
        context.insert(note)
    }
}
#endif
