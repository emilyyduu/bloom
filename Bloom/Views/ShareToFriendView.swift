import SwiftUI

/// A small sheet listing accepted friends, tap one to share a note with
/// them. Presented from a note in the Daisy Chain.
struct ShareToFriendView: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendService = FriendService.shared
    @State private var sharedWith: Set<String> = []

    var body: some View {
        NavigationStack {
            List(friendService.friends) { friend in
                Button {
                    share(with: friend)
                } label: {
                    HStack {
                        Text(friend.username)
                        Spacer()
                        if sharedWith.contains(friend.id ?? "") {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        }
                    }
                }
            }
            .overlay {
                if friendService.friends.isEmpty {
                    ContentUnavailableView(
                        "No friends yet",
                        systemImage: "person.2",
                        description: Text("Add someone in My Circle before sharing.")
                    )
                }
            }
            .navigationTitle("Share Note")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func share(with friend: FirestoreUser) {
        guard let id = friend.id else { return }
        Task {
            try? await SharingService.shared.share(note: note, with: friend)
            sharedWith.insert(id)
        }
    }
}
