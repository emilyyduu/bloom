import SwiftUI

// A friend's shared notes, grouped by year, month and day with sticky
// headers, newest first. Reached from a friend row in
// Friends or a friend tile on Home. Not wrapped in its own
// NavigationStack since it's used both pushed (Friends) and
// sheet-presented (Home), each caller supplies its own chrome.
struct FriendJournalView: View {
    let friend: FirestoreUser
    @StateObject private var listener = FriendJournalListener()

    // One pass into days, then the days (newest first) into years and
    // months. The notes within a day stay newest first.
    private var journalGroups: (notesByDay: [JournalDayKey: [FriendNote]], years: [JournalGrouping.Year]) {
        var notesByDay: [JournalDayKey: [FriendNote]] = [:]
        for note in listener.notes {
            notesByDay[JournalDayKey(note.createdAt), default: []].append(note)
        }
        for (day, notes) in notesByDay {
            notesByDay[day] = notes.sorted { $0.createdAt > $1.createdAt }
        }
        return (notesByDay, JournalGrouping.years(notesByDay.keys.sorted(by: >)))
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

    // Year headers, then month headers, then day headers, each sticky.
    private var journal: some View {
        let groups = journalGroups
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 28, pinnedViews: .sectionHeaders) {
                ForEach(groups.years) { year in
                    Section {
                        ForEach(year.months) { month in
                            Section {
                                ForEach(month.days) { day in
                                    Section {
                                        ForEach(groups.notesByDay[day] ?? []) { note in
                                            FriendNoteRow(friend: friend, note: note)
                                        }
                                    } header: {
                                        stickyHeader(dayHeaderString(day.date()), font: .headline)
                                    }
                                }
                            } header: {
                                stickyHeader(JournalFormat.monthOnly(month.key.date()), font: .title3)
                            }
                        }
                    } header: {
                        stickyHeader(JournalFormat.year(year.year), font: .title2)
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
            .padding(.horizontal)
            .padding(.bottom)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stickyHeader(_ title: String, font: Font) -> some View {
        Text(title)
            .font(font)
            .fontWeight(.bold)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
            .background(.regularMaterial)
            .accessibilityAddTraits(.isHeader)
    }
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
    let friend: FirestoreUser
    let note: FriendNote

    @State private var detail: NoteDetailRequest?

    private var friendName: String { friend.shownName }
    private var friendUID: String? { friend.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(timeString(note.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                CommentBubbleButton(ownerUID: friendUID, noteID: note.id) { open(focusComments: true) }
            }
            Text(note.text)

            if let friendUID {
                FriendVoiceMemo(friendUID: friendUID, note: note)
            }

            // Only shared notes ever reach this screen, and only the
            // ones that report a photo are fetched.
            if note.hasPhoto, let friendUID, let noteID = note.id {
                FriendNotePhoto(friendUID: friendUID, noteID: noteID)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture { open(focusComments: false) }
        .sheet(item: $detail) { request in
            NoteDetailSheet(request: request)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(friendName), \(dayHeaderString(note.createdAt)) \(timeString(note.createdAt)), \(note.text)"
                + (note.hasPhoto ? ", has a photo" : "")
                + (note.hasAudio == true ? ", has a voice memo" : "")
        )
    }
}

extension FriendNoteRow {
    fileprivate func open(focusComments: Bool) {
        guard let uid = friend.id else { return }
        detail = .friend(note, ownerUID: uid, author: friend, focusComments: focusComments)
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
