import SwiftUI
import Combine
import FirebaseFirestore

// One friend's pinned notes, live. Owned per screen rather than as a
// singleton so nothing is shared between friends: start() resets every
// property, and the listener lives only between FriendProfileView's
// onAppear and onDisappear.
//
// The query has exactly two equality filters (sharedWithFriends == true
// and isPinned == true) and no orderBy, so Firestore needs no composite
// index. Ordering by pinnedAt happens here instead.
@MainActor
final class FriendPinnedListener: ObservableObject {
    enum LoadState {
        case loading
        case loaded
        case permissionDenied
        case failed
    }

    @Published private(set) var notes: [FriendNote] = []
    @Published private(set) var state: LoadState = .loading

    private let db = Firestore.firestore()
    private var listener: ListenerRegistration?
    private var friendUID: String?

    func start(friendUID: String) {
        stop()
        self.friendUID = friendUID
        notes = []
        state = .loading

        // DEBUG sample friends are never looked up in Firestore.
        guard !friendUID.hasPrefix("sample-") else {
            #if DEBUG
            notes = Self.sampleNotes(for: friendUID)
            state = .loaded
            #endif
            return
        }

        listener = db.collection("users").document(friendUID).collection("notes")
            .whereField("sharedWithFriends", isEqualTo: true)
            .whereField("isPinned", isEqualTo: true)
            .addSnapshotListener { [weak self] snapshot, error in
                guard let self, self.friendUID == friendUID else { return }

                if let error {
                    let nsError = error as NSError
                    let isDenied = nsError.domain == FirestoreErrorDomain
                        && nsError.code == FirestoreErrorCode.permissionDenied.rawValue
                    self.state = isDenied ? .permissionDenied : .failed
                    #if DEBUG
                    logFirestoreError(error, while: "listening to \(friendUID)'s pinned notes")
                    #endif
                    return
                }

                let fetched = snapshot?.decoded(as: FriendNote.self) ?? []
                self.notes = Array(
                    fetched
                        .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
                        .prefix(Note.pinLimit)
                )
                self.state = .loaded
            }
    }

    func stop() {
        listener?.remove()
        listener = nil
    }

    #if DEBUG
    private static func sampleNotes(for friendUID: String) -> [FriendNote] {
        guard friendUID == "sample-allison" || friendUID == "sample-tom" else { return [] }
        return [
            FriendNote(
                id: "sample-pin-1",
                text: "Finally finished the FIT3178 assignment, feeling good about it.",
                createdAt: Date().addingTimeInterval(-86400 * 3),
                pinnedAt: Date().addingTimeInterval(-3600)
            ),
            FriendNote(
                id: "sample-pin-2",
                text: "Long walk by the river after work, needed that.",
                createdAt: Date().addingTimeInterval(-86400 * 9),
                pinnedAt: Date().addingTimeInterval(-7200)
            ),
        ]
    }
    #endif
}

// A friend's profile: who they are, their pinned notes, and a way into
// their full journal. Not wrapped in its own NavigationStack, like
// FriendJournalView, since it's pushed from My Circle and shown in a
// sheet from Home, each caller supplies its own chrome.
struct FriendProfileView: View {
    let friend: FirestoreUser

    @StateObject private var listener = FriendPinnedListener()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                pinnedSection
                NavigationLink {
                    FriendJournalView(friend: friend)
                } label: {
                    Label("View journal", systemImage: "book")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }
            .padding()
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(friend.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let uid = friend.id { listener.start(friendUID: uid) }
        }
        .onDisappear { listener.stop() }
    }

    private var header: some View {
        VStack(spacing: 10) {
            AvatarView(
                uid: friend.id,
                name: friend.shownName,
                hasAvatar: friend.hasAvatar ?? false,
                avatarUpdatedAt: friend.avatarUpdatedAt,
                size: 96,
                relativeTo: .largeTitle,
                maxSize: 140
            )
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(friend.shownName)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("@\(friend.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Pinned")
                .accessibilityAddTraits(.isHeader)

            switch listener.state {
            case .loading:
                ProgressView("Loading pinned notes")
                    .frame(maxWidth: .infinity)
                    .padding(16)
            case .permissionDenied:
                message(
                    "You can't see this friend's notes",
                    detail: "This can happen if you're no longer friends.",
                    systemImage: "lock"
                )
            case .failed:
                VStack(spacing: 12) {
                    message(
                        "Couldn't load pinned notes",
                        detail: "Check your connection and try again.",
                        systemImage: "exclamationmark.triangle"
                    )
                    Button("Try Again") {
                        if let uid = friend.id { listener.start(friendUID: uid) }
                    }
                    .buttonStyle(.bordered)
                }
            case .loaded where listener.notes.isEmpty:
                message("\(friend.shownName) hasn't pinned anything yet", detail: nil, systemImage: "pin")
            case .loaded:
                ForEach(listener.notes) { note in
                    FriendPinnedNoteCard(friendName: friend.shownName, friendUID: friend.id, note: note)
                }
            }
        }
    }

    private func message(_ title: String, detail: String?, systemImage: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: systemImage)
                .font(.title3)
                .accessibilityHidden(true)
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
            if let detail {
                Text(detail)
                    .font(.caption)
            }
        }
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// A friend's pinned note: date, text, and the photo if it has one,
// loaded through the same FriendNotePhoto and FriendPhotoCache the
// friend journal uses.
private struct FriendPinnedNoteCard: View {
    let friendName: String
    let friendUID: String?
    let note: FriendNote

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(note.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PinIndicator()
            }

            Text(note.text)
                .font(.subheadline)

            if note.hasPhoto, let friendUID, let noteID = note.id {
                FriendNotePhoto(friendUID: friendUID, noteID: noteID)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "Pinned by \(friendName), \(note.createdAt.formatted(date: .long, time: .omitted)), \(note.text)"
                + (note.hasPhoto ? ", has a photo" : "")
        )
    }
}

#Preview {
    NavigationStack {
        FriendProfileView(
            friend: FirestoreUser(id: "sample-allison", username: "allison", displayName: "Allison Chen", createdAt: Date())
        )
    }
}
