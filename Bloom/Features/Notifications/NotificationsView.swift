import SwiftUI

// The bell screen: friend requests still waiting on a response, then
// the live activity feed. The feed is a list bound to ActivityStore's
// array, so new items appear as they arrive.
struct NotificationsView: View {
    @StateObject private var friendService = FriendService.shared
    @StateObject private var activity = ActivityStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var errorMessage: String?
    @State private var destination: ActivityDestination?
    // What was unread when the screen opened, so the "New" markers stay
    // visible while it is open even though lastSeen moves to now.
    @State private var seenCutoff = Date()

    @ObservedObject private var blocks = BlockService.shared

    // The feed without anything from someone I have blocked.
    private var visibleItems: [ActivityItem] {
        activity.items.filter { !blocks.isBlocked($0.fromUID) }
    }

    private var isEmpty: Bool {
        friendService.pendingIncoming.isEmpty && visibleItems.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                PhoneAlertsCard()

                if !friendService.pendingIncoming.isEmpty {
                    Section {
                        ForEach(friendService.pendingIncoming) { request in
                            IncomingRequestRow(
                                request: request,
                                name: friendService.pendingRequesterProfiles[request.fromUID]?.shownName ?? "Someone",
                                username: friendService.pendingRequesterProfiles[request.fromUID]?.username,
                                profile: friendService.pendingRequesterProfiles[request.fromUID],
                                onAccept: { accept(request) },
                                onDecline: { decline(request) }
                            )
                        }
                    } header: {
                        SectionHeader("Requests")
                    }
                }

                if !visibleItems.isEmpty {
                    Section {
                        ForEach(visibleItems) { item in
                            Button {
                                if let target = ActivityDestination(item: item) { destination = target }
                            } label: {
                                ActivityRow(item: item, isUnread: item.createdAt > seenCutoff)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        SectionHeader("Activity")
                    }
                }

                if let message = errorMessage ?? activity.errorMessage {
                    Section {
                        FormErrorText(message: message)
                        if activity.state.isFinal && activity.state != .loaded && activity.state != .permissionDenied {
                            Button("Retry") { activity.retry() }
                                .frame(minHeight: 44)
                        }
                    }
                }

                Section {
                    EmptyView()
                } footer: {
                    Text("Updates appear while Bloom is open.")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.Colors.background)
            .overlay {
                if activity.isLoading && isEmpty && activity.errorMessage == nil {
                    ProgressView("Loading")
                } else if isEmpty && activity.errorMessage == nil {
                    EmptyStateView(
                        title: "Nothing new",
                        message: "Friend requests and activity will show up here.",
                        systemImage: "bell"
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
            .sheet(item: $destination) { destination in
                ActivityDestinationSheet(destination: destination)
            }
            .onAppear {
                seenCutoff = activity.lastSeen
                ActivityRouter.shared.isFeedOpen = true
                activity.markAllSeen()
                NotificationBadge.shared.feedOpened()
            }
            .onDisappear {
                ActivityRouter.shared.isFeedOpen = false
                NotificationBadge.shared.feedClosed()
            }
            .refreshesNotificationPermission()
            // Items that arrive while the screen is open are seen too,
            // so the bell badge doesn't grow behind it.
            .onChange(of: activity.items.count) { _, _ in activity.markAllSeen() }
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
