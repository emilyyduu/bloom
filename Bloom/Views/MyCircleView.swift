import SwiftUI

struct MyCircleView: View {
    @StateObject private var friendService = FriendService.shared
    @State private var isShowingAddFriend = false

    var body: some View {
        List {
            if !friendService.pendingIncoming.isEmpty {
                Section("Requests") {
                    ForEach(friendService.pendingIncoming) { request in
                        HStack {
                            Text(friendService.pendingRequesterNames[request.fromUID] ?? "Someone")
                            Spacer()
                            Button("Accept") {
                                Task { try? await friendService.acceptFriendRequest(request) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }
                }
            }

            Section("Friends") {
                ForEach(friendService.friends) { friend in
                    Text(friend.username)
                }
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
