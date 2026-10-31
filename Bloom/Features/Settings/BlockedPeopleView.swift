import SwiftUI

// Settings > Privacy > Blocked people: who I have blocked, with Unblock.
struct BlockedPeopleView: View {
    @ObservedObject private var blocks = BlockService.shared
    @State private var names: [String: String] = [:]
    @State private var errorMessage: String?

    private var sortedUIDs: [String] {
        blocks.blockedUIDs.sorted { (names[$0] ?? $0).localizedCaseInsensitiveCompare(names[$1] ?? $1) == .orderedAscending }
    }

    var body: some View {
        List {
            if blocks.blockedUIDs.isEmpty {
                Text("You haven\u{2019}t blocked anyone.")
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else {
                Section {
                    ForEach(sortedUIDs, id: \.self) { uid in
                        HStack {
                            Text(names[uid] ?? "Unknown person")
                            Spacer()
                            Button("Unblock") { unblock(uid) }
                                .buttonStyle(.bordered)
                                .accessibilityLabel("Unblock \(names[uid] ?? "this person")")
                        }
                        .frame(minHeight: 44)
                        .task(id: uid) {
                            if let profile = await UserProfileCache.shared.profile(uid: uid) {
                                names[uid] = "\(profile.shownName) @\(profile.username)"
                            }
                        }
                    }
                } footer: {
                    Text("Unblocking does not bring a friendship back. One of you would send a new request.")
                }
            }

            FormErrorText(message: errorMessage)
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Blocked people")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func unblock(_ uid: String) {
        errorMessage = nil
        Task {
            do {
                try await BlockService.shared.unblock(uid: uid)
            } catch {
                errorMessage = "Couldn\u{2019}t unblock. Try again."
            }
        }
    }
}

#Preview {
    NavigationStack { BlockedPeopleView() }
}
