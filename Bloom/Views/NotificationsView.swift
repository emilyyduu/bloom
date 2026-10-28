import SwiftUI

// The bell screen: friend requests still waiting on a response.
// Friends' shared notes live in each friend's own FriendJournalView
// now, not here, so this no longer reads the old sharedNotes
// collection.
struct NotificationsView: View {
    @StateObject private var friendService = FriendService.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if !friendService.pendingIncoming.isEmpty {
                    Section("Requests") {
                        ForEach(friendService.pendingIncoming) { request in
                            IncomingRequestRow(
                                request: request,
                                name: friendService.pendingRequesterNames[request.fromUID] ?? "Someone",
                                onAccept: { accept(request) },
                                onDecline: { decline(request) }
                            )
                        }
                    }
                }

                if let errorMessage {
                    Section {
                        FormErrorText(message: errorMessage)
                    }
                }
            }
            .overlay {
                if friendService.pendingIncoming.isEmpty {
                    ContentUnavailableView(
                        "Nothing new",
                        systemImage: "bell",
                        description: Text("Friend requests will show up here.")
                    )
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func accept(_ request: Friendship) {
        errorMessage = nil
        Task {
            do {
                try await friendService.acceptFriendRequest(request)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func decline(_ request: Friendship) {
        errorMessage = nil
        Task {
            do {
                try await friendService.declineRequest(request)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    NotificationsView()
}
