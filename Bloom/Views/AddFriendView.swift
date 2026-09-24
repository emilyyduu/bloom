import SwiftUI

/// Finding a friend works two ways: searching by username, or matching
/// against the device's own contacts. Either path ends the same way, a
/// friend request that the other person still has to accept.
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
    @State private var requestedUIDs: Set<String> = []
    @State private var isSearching = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding()
                .onChange(of: mode) { _, newMode in
                    results = []
                    errorMessage = nil
                    if newMode == .contacts { loadContacts() }
                }

                List(results) { user in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(user.username)
                            if let phone = user.phoneNumber {
                                Text(phone).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Button(requestedUIDs.contains(user.id ?? "") ? "Requested" : "Add") {
                            request(user)
                        }
                        .buttonStyle(.bordered)
                        .disabled(requestedUIDs.contains(user.id ?? ""))
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
            }
            .navigationTitle("Add Friend")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .searchable(text: $query, prompt: "Search by username")
            .onSubmit(of: .search) { searchByUsername() }
        }
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
        guard let id = user.id else { return }
        requestedUIDs.insert(id)
        Task {
            try? await friendService.sendFriendRequest(to: user)
        }
    }
}

#Preview {
    AddFriendView()
}
