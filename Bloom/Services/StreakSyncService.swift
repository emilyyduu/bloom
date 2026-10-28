import Foundation
import FirebaseAuth
import FirebaseFirestore
import SwiftData

// Writes the signed-in user's posting streak to Firestore's
// `streaks/{uid}` document, so friends' GardenService listeners can
// show it in the Shared Circle Garden. Called after a note is added to
// today and when the app returns to the foreground. Does nothing when
// signed out.
@MainActor
final class StreakSyncService {
    static let shared = StreakSyncService()
    private init() {}

    private let db = Firestore.firestore()

    func sync(context: ModelContext) async {
        guard let uid = Auth.auth().currentUser?.uid,
              StoreManager.shared.owns(context, uid: uid) else { return }

        let calendar = Calendar.current
        let postedDates = postedDates(in: context, calendar: calendar)
        guard let lastPostDate = StreakCalculator.lastPostDate(postedDates: postedDates) else { return }
        let currentStreak = StreakCalculator.currentStreak(postedDates: postedDates, today: Date(), calendar: calendar)

        let data: [String: Any] = [
            "currentStreak": currentStreak,
            "lastPostDate": Timestamp(date: lastPostDate),
            "updatedAt": Timestamp(date: Date()),
        ]

        do {
            try await db.collection("streaks").document(uid).setData(data)
        } catch {
            #if DEBUG
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                print("StreakSyncService: permission denied writing streaks/\(uid). " +
                    "The streaks Firestore security rules probably haven't been published yet.")
            } else {
                print("StreakSyncService: error writing streaks/\(uid): \(error)")
            }
            #endif
        }
    }

    private func postedDates(in context: ModelContext, calendar: Calendar) -> Set<Date> {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { !$0.isDraft })
        guard let notes = try? context.fetch(descriptor) else { return [] }
        return Set(notes.map { calendar.startOfDay(for: $0.createdAt) })
    }
}
