import SwiftUI

// Finding a friend works two ways: searching by username, or matching
// against the device's own contacts. Either path ends the same way, a
// friend request that the other person still has to accept.
struct AddFriendView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendService = FriendService.shared

    private enum Mode: String, CaseIterable {
        case username = "Username"
        case contacts = "Phone Contacts"
    }

    @State private var mode: Mode = .username
    @State private var query = ""
    @State private var results: [FirestoreUser] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var requestErrorMessage: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                modePicker
                    .padding(Theme.Spacing.lg)
                    .onChange(of: mode) { _, newMode in
                        results = []
                        errorMessage = nil
                        if newMode == .contacts { loadContacts() }
                    }

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
                .overlay {
                    if isSearching {
                        ProgressView()
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Couldn't search",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
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

    // The segmented style truncates "Username"/"Phone Contacts" at
    // accessibility sizes, so it becomes a menu instead; the binding is
    // unchanged either way, so the current choice is never lost.
    @ViewBuilder
    private var modePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Mode", selection: $mode) {
                ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
    }

    @ViewBuilder
    private func actionView(for user: FirestoreUser) -> some View {
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
        guard mode == .username, !query.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isSearching = true
        errorMessage = nil
        Task {
            do {
                results = try await friendService.searchByUsername(query)
            } catch {
                errorMessage = "Check your connection and try again."
            }
            isSearching = false
        }
    }

    private func loadContacts() {
        isSearching = true
        errorMessage = nil
        Task {
            do {
                results = try await friendService.searchByContacts()
            } catch {
                errorMessage = "Bloom needs permission to check your contacts for this."
            }
            isSearching = false
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
