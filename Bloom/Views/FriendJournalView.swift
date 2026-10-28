import SwiftUI

// A friend's shared notes, grouped by month and then day like the
// monthly journals screen, newest first. Reached from a friend row in
// My Circle or a friend tile on Home. Not wrapped in its own
// NavigationStack since it's used both pushed (My Circle) and
// sheet-presented (Home), each caller supplies its own chrome.
struct FriendJournalView: View {
    let friend: FirestoreUser
    @StateObject private var listener = FriendJournalListener()

    private var monthGroups: [FriendMonthGroup] {
        let calendar = Calendar.current

        let notesByDay = Dictionary(grouping: listener.notes) { calendar.startOfDay(for: $0.createdAt) }
        let dayGroups = notesByDay.map { day, notes in
            FriendDayGroup(day: day, notes: notes.sorted { $0.createdAt > $1.createdAt })
        }

        let daysByMonth = Dictionary(grouping: dayGroups) { group in
            calendar.dateInterval(of: .month, for: group.day)?.start ?? group.day
        }
        return daysByMonth
            .map { monthStart, days in
                FriendMonthGroup(monthStart: monthStart, days: days.sorted { $0.day > $1.day })
            }
            .sorted { $0.monthStart > $1.monthStart }
    }

    // Who this journal belongs to, above whichever state is showing.
    private var header: some View {
        HStack(spacing: 12) {
            AvatarView(user: friend, size: 56, relativeTo: .title)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(friend.shownName)
                    .font(.title3)
                    .fontWeight(.bold)
                Text("@\(friend.username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            content
        }
        .navigationTitle(friend.shownName)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startListening() }
        .onDisappear { listener.stop() }
    }

    private var content: some View {
        Group {
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
                    Button("Try Again") { startListening() }
                }
            case .loaded where listener.notes.isEmpty:
                ContentUnavailableView(
                    "\(friend.shownName) hasn't shared anything yet",
                    systemImage: "tray"
                )
            case .loaded:
                journal
            }
        }
    }

    private func startListening() {
        guard let uid = friend.id else { return }
        listener.start(friendUID: uid)
    }

    private var journal: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 28) {
                ForEach(monthGroups) { month in
                    VStack(alignment: .leading, spacing: 20) {
                        Text(monthYearString(month.monthStart))
                            .font(.title3)
                            .fontWeight(.bold)
                            .accessibilityAddTraits(.isHeader)

                        ForEach(month.days) { day in
                            VStack(alignment: .leading, spacing: 12) {
                                Text(dayHeaderString(day.day))
                                    .font(.headline)
                                    .accessibilityAddTraits(.isHeader)

                                ForEach(day.notes) { note in
                                    FriendNoteRow(friendName: friend.shownName, friendUID: friend.id, note: note)
                                }
                            }
                        }
                    }
                }

                if listener.canLoadMore {
                    Button {
                        listener.loadEarlier()
                    } label: {
                        if listener.isLoadingMore {
                            ProgressView()
                        } else {
                            Text("Load earlier")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(listener.isLoadingMore)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct FriendDayGroup: Identifiable {
    let day: Date
    let notes: [FriendNote]

    var id: Date { day }
}

private struct FriendMonthGroup: Identifiable {
    let monthStart: Date
    let days: [FriendDayGroup]

    var id: Date { monthStart }
}

private func monthYearString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("yMMMM")
    return formatter.string(from: date)
}

// Same weekday plus day and month header the monthly journals screen uses.
private func dayHeaderString(_ date: Date) -> String {
    let weekdayFormatter = DateFormatter()
    weekdayFormatter.locale = .current
    weekdayFormatter.dateFormat = "EEEE"

    let dayMonthFormatter = DateFormatter()
    dayMonthFormatter.locale = .current
    dayMonthFormatter.setLocalizedDateFormatFromTemplate("dMMMM")

    return "\(weekdayFormatter.string(from: date)) \(dayMonthFormatter.string(from: date))"
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
    let friendUID: String?
    let note: FriendNote

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(timeString(note.createdAt))
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(note.text)

            // Only shared notes ever reach this screen, and only the
            // ones that report a photo are fetched.
            if note.hasPhoto, let friendUID, let noteID = note.id {
                FriendNotePhoto(friendUID: friendUID, noteID: noteID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(friendName), \(dayHeaderString(note.createdAt)) \(timeString(note.createdAt)), \(note.text)"
                + (note.hasPhoto ? ", has a photo" : "")
        )
    }
}

// Fetched only when the row scrolls on screen (the task starts when
// the view appears), through FriendPhotoCache so a photo is never
// downloaded twice.
private struct FriendNotePhoto: View {
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
