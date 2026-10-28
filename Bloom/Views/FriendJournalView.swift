import SwiftUI

// A friend's shared notes, grouped by day, newest first. Reached from
// a friend row in My Circle or a friend tile on Home. Not wrapped in
// its own NavigationStack since it's used both pushed (My Circle) and
// sheet-presented (Home), each caller supplies its own chrome.
struct FriendJournalView: View {
    let friend: FirestoreUser
    @StateObject private var listener = FriendJournalListener()

    private var groupedNotes: [(day: Date, notes: [FriendNote])] {
        let calendar = Calendar.current
        let grouped = Dictionary(grouping: listener.notes) { calendar.startOfDay(for: $0.createdAt) }
        return grouped.keys.sorted(by: >).map { day in
            (day: day, notes: (grouped[day] ?? []).sorted { $0.createdAt > $1.createdAt })
        }
    }

    var body: some View {
        Group {
            if listener.isPermissionDenied {
                ContentUnavailableView(
                    "You can't see this friend's notes",
                    systemImage: "lock",
                    description: Text("This can happen if you're no longer friends.")
                )
            } else if listener.notes.isEmpty {
                ContentUnavailableView(
                    "\(friend.username) hasn't shared anything yet",
                    systemImage: "tray"
                )
            } else {
                List {
                    ForEach(groupedNotes, id: \.day) { group in
                        Section {
                            ForEach(group.notes) { note in
                                FriendNoteRow(friendName: friend.username, note: note)
                            }
                        } header: {
                            Text(dayHeaderString(group.day))
                                .accessibilityAddTraits(.isHeader)
                        }
                    }
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle(friend.username)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard let uid = friend.id else { return }
            listener.start(friendUID: uid)
        }
        .onDisappear {
            listener.stop()
        }
    }
}

private func dayHeaderString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("dMMMM")
    return formatter.string(from: date)
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private struct FriendNoteRow: View {
    let friendName: String
    let note: FriendNote

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(timeString(note.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 64, alignment: .leading)
            Text(note.text)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(friendName), \(dayHeaderString(note.createdAt)) \(timeString(note.createdAt)), \(note.text)"
        )
    }
}

#Preview {
    NavigationStack {
        FriendJournalView(
            friend: FirestoreUser(id: "preview", username: "Tom", usernameLower: "tom", phoneNumber: nil, createdAt: Date())
        )
    }
}
