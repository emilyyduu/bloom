import SwiftUI

// A small sheet listing accepted friends, tap one to share a note with
// them. Presented from a note in Home's timeline.
struct ShareToFriendView: View {
    let note: Note
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendService = FriendService.shared
    @State private var sharedWith: Set<String> = []
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
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
                            description: Text("Add a friend before sharing.")
                        )
                    }
                }

                FormErrorText(message: errorMessage)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
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
        errorMessage = nil
        Task {
            do {
                try await SharingService.shared.share(note: note, with: friend)
                sharedWith.insert(id)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
