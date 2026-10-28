import SwiftUI

struct MyCircleView: View {
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
                        FriendJournalView(friend: friend)
                    } label: {
                        Text(friend.username)
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
        .navigationTitle("My Circle")
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
        MyCircleView()
    }
}
