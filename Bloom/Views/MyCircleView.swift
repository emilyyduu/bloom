import SwiftUI

struct MyCircleView: View {
    @StateObject private var friendService = FriendService.shared
    @State private var isShowingAddFriend = false
    @State private var isShowingSignOutConfirmation = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
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

                FormErrorText(message: errorMessage)
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
                ToolbarItem(placement: .topBarLeading) {
                    Button("Sign Out") {
                        isShowingSignOutConfirmation = true
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isShowingAddFriend = true
                    } label: {
                        Image(systemName: "person.badge.plus")
                    }
                }
            }
            .confirmationDialog(
                "Sign out of Bloom?",
                isPresented: $isShowingSignOutConfirmation,
                titleVisibility: .visible
            ) {
                Button("Sign Out", role: .destructive) { signOut() }
                Button("Cancel", role: .cancel) {}
            }
            .sheet(isPresented: $isShowingAddFriend) {
                AddFriendView()
            }
            .task {
                friendService.startListening()
            }
        }
    }

    private func signOut() {
        FriendService.shared.stopListening()
        do {
            try AuthService.shared.signOut()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    MyCircleView()
}
