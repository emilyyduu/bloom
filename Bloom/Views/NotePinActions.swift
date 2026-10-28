import SwiftUI
import SwiftData

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

// "Pin to profile" / "Unpin" as a context menu item and as an
// accessibility action, with the three-pin limit enforced here. Apply
// it to any card or row that shows a posted note.
private struct NotePinActions: ViewModifier {
    let note: Note

    @Environment(\.modelContext) private var context
    @State private var isShowingLimitAlert = false

    private var title: LocalizedStringKey {
        note.isPinned ? "Unpin" : "Pin to profile"
    }

    func body(content: Content) -> some View {
        // Drafts can't be pinned, so they get no pin actions at all.
        if note.isDraft {
            content
        } else {
            content
                .contextMenu {
                    Button {
                        toggle()
                    } label: {
                        Label(title, systemImage: note.isPinned ? "pin.slash" : "pin")
                    }
                }
                .accessibilityAction(named: Text(title)) {
                    toggle()
                }
                .alert("Pin limit reached", isPresented: $isShowingLimitAlert) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text("You can pin up to \(Note.pinLimit) notes. Unpin one first.")
                }
        }
    }

    private func toggle() {
        if note.isPinned {
            NoteSyncService.shared.setPinned(false, for: note)
        } else if Note.pinnedCount(in: context) >= Note.pinLimit {
            isShowingLimitAlert = true
        } else {
            NoteSyncService.shared.setPinned(true, for: note)
        }
    }
}

extension View {
    func notePinActions(_ note: Note) -> some View {
        modifier(NotePinActions(note: note))
    }
}
