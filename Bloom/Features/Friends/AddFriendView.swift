import SwiftUI

// Finding a friend by searching for their username. It ends in a friend
// request that the other person still has to accept.
struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendService = FriendService.shared
    @ObservedObject private var blockService = BlockService.shared

    @State private var query = ""
    @State private var results: [FirestoreUser] = []
    @State private var hasSearched = false
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var requestErrorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                List(results) { user in
                    HStack(spacing: Theme.Spacing.md) {
                        AvatarView(user: user, size: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(user.shownName)
                            Text("@\(user.username)")
                                .textStyle(.callout)
                                .foregroundStyle(Theme.Colors.textSecondary)
                        }
                        Spacer()
                        actionView(for: user)
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Theme.Colors.background)
                .overlay {
                    if isSearching {
                        ProgressView()
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Couldn't search",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else if hasSearched, results.isEmpty {
                        ContentUnavailableView.search(text: query)
                    }
                }

                FormErrorText(message: requestErrorMessage)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
            .navigationTitle("Add Friend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(
                text: $query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search by username"
            )
            .onSubmit(of: .search) { searchByUsername() }
        }
    }

    @ViewBuilder
    private func actionView(for user: FirestoreUser) -> some View {
        if blockService.isBlocked(user.id) {
            Button("Unblock") { unblock(user) }
                .buttonStyle(.bordered)
        } else {
            relationshipAction(for: user)
        }
    }

    @ViewBuilder
    private func relationshipAction(for user: FirestoreUser) -> some View {
        switch relationship(for: user) {
        case .friends:
            Text("Friends")
                .foregroundStyle(Theme.Colors.textSecondary)
        case .outgoingPending:
            Text("Requested")
                .foregroundStyle(Theme.Colors.textSecondary)
        case .incomingPending:
            Button("Accept") { accept(user) }
                .buttonStyle(.borderedProminent)
        case .none:
            Button("Add") { request(user) }
                .buttonStyle(.bordered)
        }
    }

    private func relationship(for user: FirestoreUser) -> FriendRelationship {
        guard let id = user.id else { return .none }
        return friendService.relationship(withUID: id)
    }

    private func searchByUsername() {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                results = try await friendService.searchByUsername(query)
                hasSearched = true
            } catch {
                errorMessage = "Check your connection and try again."
            }
            isSearching = false
        }
    }

    // Unblocking doesn't restore the friendship, the button turns into Add.
    private func unblock(_ user: FirestoreUser) {
        guard let id = user.id else { return }
        requestErrorMessage = nil
        Task {
            do {
                try await blockService.unblock(uid: id)
            } catch {
                requestErrorMessage = error.localizedDescription
            }
        }
    }

    private func request(_ user: FirestoreUser) {
        requestErrorMessage = nil
        Task {
            do {
                try await friendService.sendFriendRequest(to: user)
            } catch {
                requestErrorMessage = error.localizedDescription
            }
        }
    }

    private func accept(_ user: FirestoreUser) {
        guard let id = user.id, let incoming = friendService.incomingRequest(fromUID: id) else { return }
        requestErrorMessage = nil
        Task {
            do {
                try await friendService.acceptFriendRequest(incoming)
            } catch {
                requestErrorMessage = error.localizedDescription
            }
        }
    }
}

#Preview("Large") {
    AddFriendView()
        .environment(\.dynamicTypeSize, .large)
}

#Preview("XXX Large") {
    AddFriendView()
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Accessibility 5") {
    AddFriendView()
        .environment(\.dynamicTypeSize, .accessibility5)
}
