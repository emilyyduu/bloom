import SwiftUI

// A friend's shared notes as a journal: year, then month, then a calendar,
// then a day as the chain, the same flow as my own journals. Reached from
// a friend's profile. Not wrapped in its own NavigationStack since each
// caller supplies its own chrome.
//
// The notes come from FriendJournalListener, one per screen, so nothing is
// shared between friends. Months and counts are built from what is loaded.
struct FriendJournalView: View {
    let friend: FirestoreUser
    @StateObject private var listener = FriendJournalListener()
    @StateObject private var model = JournalModel<FriendNote>()

    var body: some View {
        content
            .navigationTitle(friend.shownName)
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { startListening() }
            .onDisappear { listener.stop() }
            .onReceive(listener.$notes) { model.update(items: $0) }
    }

    @ViewBuilder
    private var content: some View {
        switch listener.state {
        case .loading:
            ProgressView("Loading notes")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .permissionDenied:
            ContentUnavailableView(
                "You can't see this friend's notes",
                systemImage: "lock",
                description: Text("This can happen if you're no longer friends.")
            )
        case .failed:
            ContentUnavailableView {
                Label("Couldn't load notes", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Retry") { startListening() }
            }
        case .loaded where listener.notes.isEmpty:
            ContentUnavailableView(
                "\(friend.shownName) hasn't shared anything yet",
                systemImage: "tray"
            )
        case .loaded:
            JournalYearsScreen(
                title: friend.shownName,
                model: model,
                source: JournalSource<FriendNote, FriendTimelineCard>(
                    owner: friend,
                    request: { note, focusComments in
                        .friend(note, ownerUID: friend.id ?? "", author: friend, focusComments: focusComments)
                    },
                    card: { note, onComment, onTap in
                        FriendTimelineCard(friend: friend, note: note, onComment: onComment, onTap: onTap)
                    }
                ),
                footnote: listener.hitLimit ? "Showing the latest \(FriendJournalListener.limit) notes" : nil
            )
        }
    }

    private func startListening() {
        guard let uid = friend.id else { return }
        listener.start(friendUID: uid)
    }
}

// Fetched only when the row scrolls on screen (the task starts when
// the view appears), through FriendPhotoCache so a photo is never
// downloaded twice.
struct FriendNotePhoto: View {
    let friendUID: String
    let noteID: String

    private enum Phase {
        case loading
        case loaded(UIImage)
        case failed
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.secondarySystemBackground))
                    .frame(height: 180)
                    .overlay { ProgressView() }
                    .accessibilityLabel("Loading photo")
            case .loaded(let image):
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Photo")
            case .failed:
                Label("Photo unavailable", systemImage: "photo.badge.exclamationmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            }
        }
        .task(id: noteID) {
            phase = .loading
            switch await FriendPhotoCache.shared.photo(ownerUID: friendUID, noteID: noteID) {
            case .image(let image): phase = .loaded(image)
            case .failed: phase = .failed
            }
        }
    }
}

#Preview {
    NavigationStack {
        FriendJournalView(
            friend: FirestoreUser(id: "preview", username: "Tom", usernameLower: "tom", phoneNumber: nil, createdAt: Date())
        )
    }
}
