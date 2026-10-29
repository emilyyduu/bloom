import SwiftUI

// The people list: incoming requests, my friends and Add Friend.
struct FriendsView: View {
    @StateObject private var friendService = FriendService.shared
    @State private var isShowingAddFriend = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    RequestsView()
                } label: {
                    HStack {
                        Label("Requests", systemImage: "person.crop.circle.badge.clock")
                        Spacer()
                        if !friendService.pendingIncoming.isEmpty {
                            Text("\(friendService.pendingIncoming.count)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section {
                ForEach(friendService.friends) { friend in
                    NavigationLink {
                        FriendProfileView(friend: friend)
                    } label: {
                        HStack(spacing: 12) {
                            AvatarView(user: friend, size: 40)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(friend.shownName)
                                Text("@\(friend.username)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                SectionHeader("Friends")
            }
        }
        .overlay {
            if friendService.friends.isEmpty && friendService.pendingIncoming.isEmpty {
                ContentUnavailableView(
                    "No friends yet",
                    systemImage: "person.2",
                    description: Text("Add someone to start sharing notes.")
                )
            }
        }
        .navigationTitle("Friends")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingAddFriend = true
                } label: {
                    Image(systemName: "person.badge.plus")
                }
            }
        }
        .sheet(isPresented: $isShowingAddFriend) {
            AddFriendView()
        }
        .task {
            friendService.startListening()
        }
    }
}

#Preview {
    NavigationStack {
        FriendsView()
    }
}
