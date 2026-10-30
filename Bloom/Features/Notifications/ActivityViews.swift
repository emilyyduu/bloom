import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore

// MARK: - Destination

// What a feed item or a tapped notification opens. A note opens the detail sheet in
// viewer mode (or owner mode when it is a comment on my own note), after
// fetching the single note document. A note that is gone says so.
struct ActivityDestinationSheet: View {
    let destination: ActivityDestination

    private enum Phase {
        case loading
        case note(NoteDetailRequest)
        case friend(FirestoreUser)
        case unavailable(String)
    }

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var phase: Phase = .loading

    var body: some View {
        switch phase {
        case .note(let request):
            NoteDetailSheet(request: request)
        case .friend(let user):
            NavigationStack {
                FriendProfileView(friend: user)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { dismiss() }
                        }
                    }
            }
        case .loading:
            shell { ProgressView("Loading").frame(maxWidth: .infinity, maxHeight: .infinity) }
                .task { await load() }
        case .unavailable(let message):
            shell {
                ContentUnavailableView(message, systemImage: "tray")
            }
        }
    }

    private func shell<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        NavigationStack {
            content()
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }

    private func load() async {
        switch destination {
        case .feed:
            dismiss()
        case .friend(let uid):
            if let user = await UserProfileCache.shared.profile(uid: uid) {
                phase = .friend(user)
            } else {
                phase = .unavailable("This person isn\u{2019}t available")
            }
        case .note(let ownerUID, let noteID, let focusComments):
            phase = await loadNote(ownerUID: ownerUID, noteID: noteID, focusComments: focusComments)
        }
    }

    private func loadNote(ownerUID: String, noteID: String, focusComments: Bool) async -> Phase {
        let gone = Phase.unavailable("This note is no longer available")

        // A comment on my own note: the note is local.
        if ownerUID == Auth.auth().currentUser?.uid {
            guard let uuid = UUID(uuidString: noteID) else { return gone }
            var descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.id == uuid })
            descriptor.fetchLimit = 1
            guard let note = try? context.fetch(descriptor).first, !note.isDraft else { return gone }
            return .note(.mine(note, focusComments: focusComments))
        }

        do {
            let snapshot = try await Firestore.firestore().collection("users").document(ownerUID)
                .collection("notes").document(noteID).getDocument()
            guard snapshot.exists, let note = try? snapshot.data(as: FriendNote.self) else { return gone }
            // Friends see only today's notes and pinned ones, so an older
            // note opened from a notification shows no content.
            guard FriendDay().contains(note.createdAt) || note.pinnedAt != nil else {
                return .unavailable("This note is from an earlier day")
            }
            let author = await UserProfileCache.shared.profile(uid: ownerUID)
            return .note(.friend(note, ownerUID: ownerUID, author: author, focusComments: focusComments))
        } catch {
            // Stopped sharing or no longer friends reads as gone too.
            return gone
        }
    }
}

// MARK: - Feed row

struct ActivityRow: View {
    let item: ActivityItem
    let isUnread: Bool

    @State private var author: FirestoreUser?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var name: String { author?.shownName ?? "Someone" }

    private var title: String {
        switch item.kind {
        case .note: return "\(name) shared a note"
        case .comment:
            // A reply's preview already starts with "replied: ".
            if let preview = item.preview, preview.hasPrefix("replied: ") { return "\(name) \(preview)" }
            if let preview = item.preview, !preview.isEmpty { return "\(name) commented: \(preview)" }
            return "\(name) commented"
        case .reaction: return "\(name) reacted to your note"
        case .accepted: return "\(name) accepted your request"
        }
    }

    private var relativeTime: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: item.createdAt, relativeTo: Date())
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(
                uid: item.fromUID,
                name: name,
                hasAvatar: author?.hasAvatar ?? false,
                avatarUpdatedAt: author?.avatarUpdatedAt,
                size: 40,
                relativeTo: .body
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.subheadline)
                    .frame(maxWidth: .infinity, alignment: .leading)
                if item.kind == .note, let preview = item.preview, !preview.isEmpty {
                    Text(preview)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    Text(relativeTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    // A word as well as colour.
                    if isUnread {
                        Text("New")
                            .font(.caption2)
                            .fontWeight(.bold)
                            .foregroundStyle(Color(.systemBackground))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.accentColor))
                    }
                }
            }
        }
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(isUnread ? "New. " : "")\(title), \(relativeTime)")
        .accessibilityAddTraits(.isButton)
        .task(id: item.fromUID) {
            author = await UserProfileCache.shared.profile(uid: item.fromUID)
        }
    }
}
