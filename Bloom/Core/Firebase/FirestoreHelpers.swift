import FirebaseFirestore

extension QuerySnapshot {
    // Decodes every document in the snapshot as `T`, silently skipping
    // any that fail to decode. Used wherever a Firestore collection
    // (users, friendships, sharedNotes) is read into one of this app's
    // Codable models.
    func decoded<T: Decodable>(as type: T.Type) -> [T] {
        documents.compactMap { try? $0.data(as: T.self) }
    }
}

#if DEBUG
// A shared way to print a Firestore error during development. A
// permission denied error almost always means the security rules for
// that path haven't been published yet, so it gets called out
// specifically rather than dumped as a raw NSError.
func logFirestoreError(_ error: Error, while action: String) {
    let nsError = error as NSError
    if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
        print("Firestore: permission denied while \(action). Check that your security rules are published.")
    } else {
        print("Firestore: error while \(action): \(error)")
    }
}
#endif
