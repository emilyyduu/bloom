import SwiftUI

// What a friend has shared today, and nothing older: their shared, posted
// notes from the start of my current calendar day to the start of the next,
// as the same chain Home uses, oldest first. Reached from a friend's
// profile. Not wrapped in its own NavigationStack since each caller
// supplies its own chrome.
//
// The notes come from FriendTodayListener, one per screen, so nothing is
// shared between friends. It restarts when the day changes, so a note
// drops off at midnight.
struct FriendTodayView: View {
    let friend: FirestoreUser

    @StateObject private var listener = FriendTodayListener()
    @State private var detail: NoteDetailRequest?
    @Environment(\.scenePhase) private var scenePhase

    private var title: String { "\(friend.shownName)\u{2019}s notes" }

    var body: some View {
        content
            .background(Color(.systemGroupedBackground))
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { startListening() }
            .onDisappear { listener.stop() }
            .onChange(of: scenePhase) { _, newPhase in
                if newPhase == .active { listener.refreshDayIfNeeded() }
            }
            // Midnight while the screen is open, and the device date
            // being changed.
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                    listener.refreshDayIfNeeded()
                }
            }
            .sheet(item: $detail) { request in
                NoteDetailSheet(request: request)
            }
    }

    @ViewBuilder
    private var content: some View {
        switch listener.state {
        case .loading:
            VStack(spacing: 0) {
                header
                ProgressView("Loading notes")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .permissionDenied:
            VStack(spacing: 0) {
                header
                ContentUnavailableView(
                    "You can\u{2019}t see this friend\u{2019}s notes",
                    systemImage: "lock",
                    description: Text("This can happen if you\u{2019}re no longer friends.")
                )
                .frame(maxHeight: .infinity)
            }
        case .failed, .missingIndex:
            VStack(spacing: 0) {
                header
                ContentUnavailableView {
                    Label("Couldn\u{2019}t load notes", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(listener.state == .missingIndex
                         ? "Today\u{2019}s notes aren\u{2019}t available yet."
                         : "Check your connection and try again.")
                } actions: {
                    Button("Retry") { listener.restart() }
                        .frame(minHeight: 44)
                }
                .frame(maxHeight: .infinity)
            }
        case .loaded where listener.notes.isEmpty:
            VStack(spacing: 0) {
                header
                ContentUnavailableView(
                    "Nothing shared today",
                    systemImage: "tray",
                    description: Text("\(friend.shownName) hasn\u{2019}t shared a note today.")
                )
                .frame(maxHeight: .infinity)
            }
        case .loaded:
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(listener.notes.enumerated()), id: \.element.id) { position, note in
                            TimelineRow(date: note.createdAt, isLast: position == listener.notes.count - 1) {
                                FriendTimelineCard(
                                    friend: friend,
                                    note: note,
                                    onComment: { open(note, focusComments: true) },
                                    onTap: { open(note, focusComments: false) }
                                )
                            }
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 700, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
        }
    }

    // "Alex's notes" with the day under it, for the day the listener is on.
    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.title2)
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            Text(Self.dayFormatter.string(from: listener.day.start))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding([.horizontal, .top])
        .accessibilityElement(children: .combine)
    }

    // "Thursday 29 October", in the viewer's language and order.
    private static let dayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("EEEEdMMMM")
        return formatter
    }()

    private func open(_ note: FriendNote, focusComments: Bool) {
        guard let uid = friend.id else { return }
        detail = .friend(note, ownerUID: uid, author: friend, focusComments: focusComments)
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
        FriendTodayView(
            friend: FirestoreUser(id: "preview", username: "Tom", usernameLower: "tom", phoneNumber: nil, createdAt: Date())
        )
    }
}
