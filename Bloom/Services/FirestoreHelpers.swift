import FirebaseFirestore

extension QuerySnapshot {
    /// Decodes every document in the snapshot as `T`, silently skipping
    /// any that fail to decode. Used wherever a Firestore collection
    /// (users, friendships, sharedNotes) is read into one of this app's
    /// Codable models.
    func decoded<T: Decodable>(as type: T.Type) -> [T] {
        documents.compactMap { try? $0.data(as: T.self) }
    }
}
