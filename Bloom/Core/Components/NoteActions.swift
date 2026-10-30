import SwiftUI
import SwiftData
import Combine

// The one place a note's actions live: Share with friends or Stop
// sharing, Pin or Unpin, Edit and Delete. The detail sheet's three dot
// menu, a card's press and hold menu and the VoiceOver actions all use
// this controller and NoteActionButtons, so nothing is duplicated.
@MainActor
final class NoteActionController: ObservableObject {
    let note: Note

    @Published var isShowingShareConfirmation = false
    @Published var isShowingStopSharingConfirmation = false
    @Published var isShowingDeleteConfirmation = false
    @Published var isShowingPinLimit = false
    @Published var errorMessage: String?
    @Published var noteToEdit: Note?

    // Set by whoever shows the actions: the model context to work in,
    // and what to do once the note is gone (the detail sheet closes).
    var context: ModelContext?
    var onDeleted: (() -> Void)?

    init(note: Note) {
        self.note = note
    }

    var isShared: Bool { note.sharedWithFriends }
    var isPinned: Bool { note.isPinned }

    // MARK: Share

    func requestShareToggle() {
        guard !note.isDraft else { return }
        if note.sharedWithFriends {
            isShowingStopSharingConfirmation = true
        } else if AccountDefaults.hasConfirmedShareToCircle {
            setShared(true)
        } else {
            isShowingShareConfirmation = true
        }
    }

    func confirmShare() {
        AccountDefaults.hasConfirmedShareToCircle = true
        setShared(true)
    }

    func confirmStopSharing() {
        setShared(false)
    }

    // updateSharedWithFriends sets the flag, clears syncedAt, uploads
    // (which stamps updatedAt) and puts the flag back if the upload
    // fails.
    private func setShared(_ isShared: Bool) {
        errorMessage = nil
        Task {
            do {
                try await NoteSyncService.shared.updateSharedWithFriends(isShared, for: note)
            } catch {
                errorMessage = "Couldn\u{2019}t update sharing. Check your connection and try again."
            }
        }
    }

    // MARK: Pin

    // The existing pin logic, including the limit of three.
    func togglePin() {
        guard !note.isDraft else { return }
        if note.isPinned {
            NoteSyncService.shared.setPinned(false, for: note)
        } else if let context, Note.pinnedCount(in: context) >= Note.pinLimit {
            isShowingPinLimit = true
        } else {
            NoteSyncService.shared.setPinned(true, for: note)
        }
    }

    // MARK: Edit and delete

    func edit() {
        guard !note.isDraft else { return }
        noteToEdit = note
    }

    func requestDelete() {
        isShowingDeleteConfirmation = true
    }

    func confirmDelete() {
        guard let context else { return }
        guard let noteID = NoteSyncService.shared.beginDeletion(of: note, context: context) else { return }
        onDeleted?()
        Task { await NoteSyncService.shared.finishDeletion(noteID: noteID, context: context) }
    }
}

// The four items, in menu order, with Delete last under a divider.
struct NoteActionButtons: View {
    @ObservedObject var controller: NoteActionController

    var body: some View {
        Button {
            controller.requestShareToggle()
        } label: {
            Label(
                controller.isShared ? "Stop sharing" : "Share with friends",
                systemImage: controller.isShared ? "person.2.slash" : "person.2"
            )
        }

        Button {
            controller.togglePin()
        } label: {
            Label(controller.isPinned ? "Unpin" : "Pin to profile", systemImage: controller.isPinned ? "pin.slash" : "pin")
        }

        Button {
            controller.edit()
        } label: {
            Label("Edit", systemImage: "pencil")
        }

        Divider()

        Button(role: .destructive) {
            controller.requestDelete()
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }
}

// Confirmations, the pin limit alert, the sharing error and the edit
// composer, attached once next to whatever shows the actions.
private struct NoteActionDialogs: ViewModifier {
    @ObservedObject var controller: NoteActionController

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Share with friends?",
                isPresented: $controller.isShowingShareConfirmation,
                titleVisibility: .visible
            ) {
                Button("Share with friends") { controller.confirmShare() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Friends see the notes you share from today and your pinned notes. They can comment on this note.")
            }
            .confirmationDialog(
                "Stop sharing?",
                isPresented: $controller.isShowingStopSharingConfirmation,
                titleVisibility: .visible
            ) {
                Button("Stop sharing", role: .destructive) { controller.confirmStopSharing() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Friends will no longer see this note. Its comments stay hidden until you share it again.")
            }
            .confirmationDialog(
                "Delete this note?",
                isPresented: $controller.isShowingDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) { controller.confirmDelete() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("It will be removed from your journal, your backup and friends\u{2019} views, along with its comments. This can\u{2019}t be undone.")
            }
            .alert("Pin limit reached", isPresented: $controller.isShowingPinLimit) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("You can pin up to \(Note.pinLimit) notes. Unpin one first.")
            }
            .alert(
                "Something went wrong",
                isPresented: Binding(
                    get: { controller.errorMessage != nil },
                    set: { if !$0 { controller.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(controller.errorMessage ?? "")
            }
            .sheet(item: $controller.noteToEdit) { note in
                NoteComposerView(editing: note)
            }
    }
}

extension View {
    func noteActionDialogs(_ controller: NoteActionController) -> some View {
        modifier(NoteActionDialogs(controller: controller))
    }
}

// Press and hold menu plus VoiceOver actions for a card or row that
// shows a posted note. Drafts get none, they open in the composer.
private struct NoteActionsModifier: ViewModifier {
    @StateObject private var controller: NoteActionController
    @Environment(\.modelContext) private var context

    init(note: Note) {
        _controller = StateObject(wrappedValue: NoteActionController(note: note))
    }

    func body(content: Content) -> some View {
        if controller.note.isDraft {
            content
        } else {
            content
                .contextMenu { NoteActionButtons(controller: controller) }
                .accessibilityAction(named: Text(controller.isShared ? "Stop sharing" : "Share with friends")) {
                    controller.requestShareToggle()
                }
                .accessibilityAction(named: Text(controller.isPinned ? "Unpin" : "Pin to profile")) {
                    controller.togglePin()
                }
                .accessibilityAction(named: Text("Edit")) { controller.edit() }
                .accessibilityAction(named: Text("Delete")) { controller.requestDelete() }
                .onAppear { controller.context = context }
                .noteActionDialogs(controller)
        }
    }
}

extension View {
    func noteActions(_ note: Note) -> some View {
        modifier(NoteActionsModifier(note: note))
    }
}

// A small pin on a note that's pinned to my profile. The word "Pinned"
// is the VoiceOver label, so the state doesn't rely on the icon alone.
struct PinIndicator: View {
    var body: some View {
        Image(systemName: "pin.fill")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .accessibilityLabel("Pinned")
    }
}

// The comment bubble on a card. Shows the cached count when there is
// one and puts it in the accessibility label. The count loads lazily
// when the card appears, and a failed load simply shows no number.
struct CommentBubbleButton: View {
    let ownerUID: String?
    let noteID: String?
    // Only shared notes have comments.
    var isEnabled = true
    let action: () -> Void

    @ObservedObject private var counts = CommentCounts.shared

    private var count: Int? {
        isEnabled ? counts.count(ownerUID: ownerUID, noteID: noteID) : nil
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "bubble.left")
                if let count, count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(.secondary)
            .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(label)
        .accessibilityHint("Opens the note at its comments")
        .task(id: noteID) {
            guard isEnabled else { return }
            await counts.ensure(ownerUID: ownerUID, noteID: noteID)
        }
    }

    private var label: String {
        guard let count else { return "Comments" }
        return "\(count) comment\(count == 1 ? "" : "s")"
    }
}
