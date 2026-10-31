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
}

// A friend's profile: who they are, their pinned notes, and a way into
// the notes they shared today. Not wrapped in its own NavigationStack, like
// FriendTodayView, since it's pushed from Friends and shown in a
// sheet from Home, each caller supplies its own chrome.
struct FriendProfileView: View {
    let friend: FirestoreUser

    @StateObject private var listener = FriendPinnedListener()
    @ObservedObject private var circleStore = CircleStore.shared

    @State private var isShowingNewCircle = false
    @State private var alertMessage: String?

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                header
                circleMenu
                pinnedSection
                NavigationLink {
                    FriendTodayView(friend: friend)
                } label: {
                    // Wraps onto more lines at large text sizes.
                    Label("View \(friend.shownName)\u{2019}s notes", systemImage: "note.text")
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bloomPrimary)
            }
            .padding(Theme.Spacing.lg)
            .frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
        }
        .background(Theme.Colors.background)
        .navigationTitle(friend.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if let uid = friend.id { listener.start(friendUID: uid) }
        }
        .onDisappear { listener.stop() }
        .sheet(isPresented: $isShowingNewCircle) {
            NewCircleSheet(preselected: friend.id.map { [$0] } ?? [])
        }
        .alert(
            "Couldn\u{2019}t change the circle",
            isPresented: Binding(get: { alertMessage != nil }, set: { if !$0 { alertMessage = nil } })
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(alertMessage ?? "")
        }
        .task { circleStore.startListening() }
    }

    // MARK: Circles

    // The checkmarks come from the circles already loaded, so showing the
    // menu never reads Firestore.
    private var circleMenu: some View {
        Menu {
            ForEach(circleStore.circles) { circle in
                Toggle(circle.name, isOn: Binding(
                    get: { isIn(circle) },
                    set: { _ in toggle(circle) }
                ))
            }
            if !circleStore.circles.isEmpty {
                Divider()
            }
            Button {
                newCircle()
            } label: {
                Label("New circle", systemImage: "plus")
            }
        } label: {
            Label("Add to circle", systemImage: "circle.grid.2x2")
                .frame(maxWidth: .infinity, minHeight: 44)
        }
        .buttonStyle(.bloomSecondary)
    }

    private func isIn(_ circle: FriendCircle) -> Bool {
        guard let id = friend.id else { return false }
        return circleStore.memberUIDs(of: circle).contains(id)
    }

    private func toggle(_ circle: FriendCircle) {
        guard let id = friend.id else { return }
        if !isIn(circle), !CircleLimits.canAdd(current: circleStore.memberUIDs(of: circle).count) {
            alertMessage = "\(circle.name) already has \(CircleLimits.maxMembers) people. A circle can have up to \(CircleLimits.maxMembers) people."
            return
        }
        Task {
            do {
                try await circleStore.toggle(id, in: circle)
            } catch {
                alertMessage = error.localizedDescription
            }
        }
    }

    private func newCircle() {
        guard CircleLimits.canAdd(current: circleStore.circles.count, limit: CircleLimits.maxCircles) else {
            alertMessage = CircleError.limitOfCircles.localizedDescription
            return
        }
        isShowingNewCircle = true
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
                    .textStyle(.heading)
                    .fontWeight(.bold)
                Text("@\(friend.username)")
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)
        }
        .frame(maxWidth: .infinity)
    }

    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            SectionHeader("Pinned")
                .accessibilityAddTraits(.isHeader)

            switch listener.state {
            case .loading:
                ProgressView("Loading pinned notes")
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.lg)
            case .permissionDenied:
                message(
                    "You can't see this friend's notes",
                    detail: "This can happen if you're no longer friends.",
                    systemImage: "lock"
                )
            case .failed:
                VStack(spacing: Theme.Spacing.md) {
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
                    FriendPinnedNoteCard(friend: friend, note: note)
                }
            }
        }
    }

    private func message(_ title: String, detail: String?, systemImage: String) -> some View {
        VStack(spacing: Theme.Spacing.sm) {
            Image(systemName: systemImage)
                .textStyle(.heading)
                .accessibilityHidden(true)
            Text(title)
                .textStyle(.callout)
                .fontWeight(.medium)
            if let detail {
                Text(detail)
                    .textStyle(.caption)
            }
        }
        .foregroundStyle(Theme.Colors.textSecondary)
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.lg)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.Colors.surfaceMuted))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.Colors.separator, lineWidth: 1))
        .accessibilityElement(children: .combine)
    }
}

// A friend's pinned note: date, text, and the photo if it has one,
// loaded through the same FriendNotePhoto and FriendPhotoCache the
// friend's today view uses.
private struct FriendPinnedNoteCard: View {
    let friend: FirestoreUser
    let note: FriendNote

    @State private var detail: NoteDetailRequest?

    private var friendName: String { friend.shownName }
    private var friendUID: String? { friend.id }

    private func open(focusComments: Bool) {
        guard let uid = friend.id else { return }
        detail = .friend(note, ownerUID: uid, author: friend, focusComments: focusComments)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack(spacing: 6) {
                Text(note.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                PinIndicator()
                Spacer()
                CommentBubbleButton(ownerUID: friendUID, noteID: note.id) { open(focusComments: true) }
            }

            Text(note.text)
                .textStyle(.callout)

            if let friendUID {
                FriendVoiceMemo(friendUID: friendUID, note: note)
            }

            if note.hasPhoto, let friendUID, let noteID = note.id {
                FriendNotePhoto(friendUID: friendUID, noteID: noteID)
            }
        }
        .padding(Theme.Spacing.lg)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.Colors.surfaceMuted))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.Colors.separator, lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        .onTapGesture { open(focusComments: false) }
        .sheet(item: $detail) { request in
            NoteDetailSheet(request: request)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "Pinned by \(friendName), \(note.createdAt.formatted(date: .long, time: .omitted)), \(note.text)"
                + (note.hasPhoto ? ", has a photo" : "")
                + (note.hasAudio == true ? ", has a voice memo" : "")
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
