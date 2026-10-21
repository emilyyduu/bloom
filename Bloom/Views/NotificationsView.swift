import SwiftUI

// The bell screen: friend requests still waiting on a response, then
// the most recent notes friends have shared. Opening this screen is
// what clears the bell's red dot, HomeView updates the
// lastSeenNotificationsTimestamp the moment this sheet is presented.
struct NotificationsView: View {
    @StateObject private var friendService = FriendService.shared
    @StateObject private var sharedNotesStore = SharedNotesStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?

    private var recentSharedNotes: [SharedNote] {
        Array(sharedNotesStore.recentNotes.prefix(10))
    }

    private var hasContent: Bool {
        !friendService.pendingIncoming.isEmpty || !recentSharedNotes.isEmpty
    }

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

                if !recentSharedNotes.isEmpty {
                    Section("Shared with you") {
                        ForEach(recentSharedNotes) { shared in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(senderName(for: shared.fromUID))
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                Text(shared.text)
                                Text(shared.sharedAt, style: .relative)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
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
                if !hasContent {
                    ContentUnavailableView(
                        "Nothing new",
                        systemImage: "bell",
                        description: Text("Friend requests and shared notes will show up here.")
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

    private func senderName(for uid: String) -> String {
        friendService.friends.first { $0.id == uid }?.username ?? "Someone"
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
