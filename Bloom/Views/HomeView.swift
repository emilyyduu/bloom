import SwiftUI
import SwiftData
import FirebaseAuth

// The landing tab: today's date and streak, today's timeline of
// notes, and what friends have shared. The bell holds requests and
// shares; the centre Add tab and the Greenhouse tab own the rest.
struct HomeView: View {
    @Binding var selectedTab: ContentView.Tab

    @Query(Note.todaysNotesDescriptor()) private var todaysNotes: [Note]
    @Query(filter: #Predicate<Note> { !$0.isDraft }, sort: \Note.createdAt) private var postedNotes: [Note]

    @StateObject private var friendService = FriendService.shared
    @StateObject private var activity = ActivityStore.shared
    @StateObject private var friendJournalService = FriendJournalService.shared

    @State private var isShowingComposer = false
    @State private var isShowingAddFriend = false
    @State private var isShowingNotifications = false
    @State private var noteDetail: NoteDetailRequest?
    @State private var selectedFriendForJournal: FirestoreUser?
    @State private var isOnScreen = false

    #if DEBUG
    @AppStorage("gardenSampleDataEnabled") private var isSampleDataEnabled = false
    #endif

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .caption) private var timeColumnWidth: CGFloat = 44
    @ScaledMetric(relativeTo: .body) private var minFriendTileWidth: CGFloat = 150

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    // In landscape on iPhone (compact height), the timeline and Friends
    // sit side by side instead of one above the other, but both stay
    // inside the one ScrollView so scroll position survives rotation.
    private var columnsLayout: AnyLayout {
        isCompactHeight
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 20))
            : AnyLayout(VStackLayout(spacing: 28))
    }

    private var dateTitle: String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("dMMMM")
        return formatter.string(from: Date())
    }

    private var currentStreak: Int {
        let calendar = Calendar.current
        let postedDates = Set(postedNotes.map { calendar.startOfDay(for: $0.createdAt) })
        return StreakCalculator.currentStreak(postedDates: postedDates, today: Date(), calendar: calendar)
    }

    // Requests waiting on me plus activity I haven't seen.
    private var unseenCount: Int {
        friendService.pendingIncoming.count + activity.unreadCount
    }

    private var displayedFriends: [FirestoreUser] {
        #if DEBUG
        if isSampleDataEnabled { return Self.sampleFriends }
        #endif
        return friendService.friends
    }

    private func loadState(for friend: FirestoreUser) -> LiveState {
        #if DEBUG
        if isSampleDataEnabled { return .loaded }
        #endif
        guard let id = friend.id else { return .loaded }
        return friendJournalService.loadState(for: id)
    }

    private var displayedLatestNoteByFriend: [String: FriendNote] {
        #if DEBUG
        if isSampleDataEnabled { return Self.sampleLatestNoteByFriend }
        #endif
        return friendJournalService.latestNoteByFriend
    }

    // The friends whose tiles get a live listener, scoped to the friends
    // actually shown here rather than any broader list.
    private var friendUIDsForTileRefresh: [String] {
        #if DEBUG
        if isSampleDataEnabled { return [] }
        #endif
        return friendService.friends.compactMap(\.id)
    }

    // Friends with a share sort newest first; everyone else sorts
    // alphabetically after them.
    private var sortedFriendTiles: [FriendTileItem] {
        let latest = displayedLatestNoteByFriend

        let withShare = displayedFriends
            .compactMap { friend -> (FirestoreUser, FriendNote)? in
                guard let id = friend.id, let note = latest[id] else { return nil }
                return (friend, note)
            }
            .sorted { $0.1.createdAt > $1.1.createdAt }
            .map { FriendTileItem(id: $0.0.id ?? $0.0.username, friend: $0.0, note: $0.1, loadState: .loaded) }

        let withoutShare = displayedFriends
            .filter { ($0.id).map { latest[$0] == nil } ?? true }
            .sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
            .map { FriendTileItem(id: $0.id ?? $0.username, friend: $0, note: nil, loadState: loadState(for: $0)) }

        return withShare + withoutShare
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(dateTitle) {
                    bellButton
                }

                streakLine
                    .padding(.horizontal)
                    .padding(.bottom, 12)

                ScrollView {
                    columnsLayout {
                        timelineSection
                            .frame(maxWidth: isCompactHeight ? 360 : .infinity, alignment: .leading)
                        friendsSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal)
                    .padding(.bottom, 24)
                }
                .refreshable {
                    friendJournalService.syncListeners(for: friendUIDsForTileRefresh)
                    await friendJournalService.refreshLatestNotes(for: friendUIDsForTileRefresh)
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(dateTitle)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingComposer) {
                NoteComposerView()
            }
            .sheet(isPresented: $isShowingAddFriend) {
                AddFriendView()
            }
            .sheet(isPresented: $isShowingNotifications) {
                NotificationsView()
            }
            .sheet(item: $noteDetail) { request in
                NoteDetailSheet(request: request)
            }
            .sheet(item: $selectedFriendForJournal) { friend in
                NavigationStack {
                    FriendProfileView(friend: friend)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Done") { selectedFriendForJournal = nil }
                            }
                        }
                }
            }
            .task {
                friendService.startListening()
            }
            // One tile listener per visible friend, attached while Home is
            // on screen. The id restarts this when the friend list or the
            // account changes (friends arrive after launch), so it never
            // depends on the list being ready at first appearance.
            .task(id: TileListenerKey(uid: Auth.auth().currentUser?.uid, friendUIDs: friendUIDsForTileRefresh)) {
                guard isOnScreen else { return }
                friendJournalService.syncListeners(for: friendUIDsForTileRefresh)
                await friendJournalService.refreshLatestNotes(for: friendUIDsForTileRefresh)
            }
            .onAppear {
                isOnScreen = true
                friendJournalService.syncListeners(for: friendUIDsForTileRefresh)
            }
            .onDisappear {
                isOnScreen = false
                friendJournalService.stopAllListeners()
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active, isOnScreen else { return }
                friendJournalService.syncListeners(for: friendUIDsForTileRefresh)
                Task { await friendJournalService.refreshLatestNotes(for: friendUIDsForTileRefresh) }
            }
        }
    }

    private var bellButton: some View {
        Button {
            isShowingNotifications = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "bell")
                    .font(.title3)
                if unseenCount > 0 {
                    Text(unseenCount > 9 ? "9+" : "\(unseenCount)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.red))
                        .offset(x: 8, y: -6)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Notifications")
        .accessibilityValue(unseenCount > 0 ? "\(unseenCount) new" : "")
    }

    private var streakLine: some View {
        Button {
            selectedTab = .greenhouse
        } label: {
            Text("Streaks: \(currentStreak) day\(currentStreak == 1 ? "" : "s")")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Today's timeline

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            if todaysNotes.isEmpty {
                emptyTimelineState
            } else {
                ForEach(Array(todaysNotes.enumerated()), id: \.element.id) { index, note in
                    TimelineRow(
                        note: note,
                        isLast: index == todaysNotes.count - 1,
                        timeColumnWidth: timeColumnWidth,
                        onComment: { noteDetail = .mine(note, focusComments: true) },
                        onTap: { noteDetail = .mine(note) }
                    )
                }
            }
        }
    }

    private var emptyTimelineState: some View {
        VStack(spacing: 12) {
            Text("No notes yet today")
                .font(.headline)
                .foregroundStyle(.secondary)
            Button("Add Note") {
                isShowingComposer = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader("Friends’ journals")
                .accessibilityAddTraits(.isHeader)

            if displayedFriends.isEmpty {
                emptyFriendsState
            } else {
                friendsGrid
            }
        }
    }

    private var friendsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minFriendTileWidth), spacing: 12)], spacing: 12) {
            ForEach(sortedFriendTiles) { tile in
                FriendTile(
                    friend: tile.friend,
                    sharedNote: tile.note,
                    loadState: tile.loadState,
                    onRetry: { if let uid = tile.friend.id { friendJournalService.retry(uid) } },
                    onOpenNote: {
                        // The tile already loaded this note, so the sheet reuses it.
                        guard let note = tile.note, let uid = tile.friend.id else {
                            selectedFriendForJournal = tile.friend
                            return
                        }
                        noteDetail = .friend(note, ownerUID: uid, author: tile.friend)
                    },
                    onOpenProfile: { selectedFriendForJournal = tile.friend }
                )
            }
        }
    }

    private var emptyFriendsState: some View {
        VStack(spacing: 12) {
            Text("Add friends to see what they share")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add Friend") {
                isShowingAddFriend = true
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    #if DEBUG
    // Four fake friends, one of them with nothing shared, so every
    // tile state can be checked without writing anything to Firestore.
    private static let sampleFriends: [FirestoreUser] = [
        FirestoreUser(id: "sample-allison", username: "allison", displayName: "Allison Chen", usernameLower: "allison", phoneNumber: nil, createdAt: Date()),
        FirestoreUser(id: "sample-priya", username: "priya", displayName: "Priya Raman", usernameLower: "priya", phoneNumber: nil, createdAt: Date()),
        FirestoreUser(id: "sample-tom", username: "tom", displayName: "Tom Nguyen", usernameLower: "tom", phoneNumber: nil, createdAt: Date()),
        FirestoreUser(id: "sample-mei", username: "mei", displayName: "Mei Tanaka", usernameLower: "mei", phoneNumber: nil, createdAt: Date()),
    ]

    private static let sampleLatestNoteByFriend: [String: FriendNote] = [
        "sample-allison": FriendNote(
            id: "sample-note-1",
            text: "Finally finished the FIT3178 assignment, feeling good about it.",
            createdAt: Date().addingTimeInterval(-3600)
        ),
        "sample-tom": FriendNote(
            id: "sample-note-2",
            text: "Coffee with the team was great today, long overdue catch up.",
            createdAt: Date().addingTimeInterval(-7200)
        ),
        "sample-mei": FriendNote(
            id: "sample-note-3",
            text: "Long walk by the river after work, needed that.",
            createdAt: Date().addingTimeInterval(-86400)
        ),
    ]
    #endif
}

// MARK: - Supporting types

private struct TileListenerKey: Equatable {
    let uid: String?
    let friendUIDs: [String]
}

struct FriendTileItem: Identifiable {
    let id: String
    let friend: FirestoreUser
    let note: FriendNote?
    let loadState: LiveState
}

// MARK: - Date and time helpers

private struct TimeDisplay {
    let value: String
    let period: String?
}

// Splits a time into its numeric value and, for 12-hour locales, a
// separate AM/PM part so the narrow time column can wrap the period
// under the value instead of truncating it.
private func timeDisplay(for date: Date) -> TimeDisplay {
    let locale = Locale.current
    if let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale),
       template.contains("a") {
        let valueFormatter = DateFormatter()
        valueFormatter.locale = locale
        valueFormatter.dateFormat = "h:mm"
        let periodFormatter = DateFormatter()
        periodFormatter.locale = locale
        periodFormatter.dateFormat = "a"
        return TimeDisplay(value: valueFormatter.string(from: date), period: periodFormatter.string(from: date))
    }
    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.dateFormat = "HH:mm"
    return TimeDisplay(value: formatter.string(from: date), period: nil)
}

private func timeString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.dateStyle = .none
    formatter.timeStyle = .short
    return formatter.string(from: date)
}

private func longDateString(_ date: Date) -> String {
    let formatter = DateFormatter()
    formatter.locale = .current
    formatter.setLocalizedDateFormatFromTemplate("dMMMM")
    return formatter.string(from: date)
}

// A locale-aware day/month short date, like "13/10", following whichever
// of day or month the locale normally puts first.
private func shortDateString(_ date: Date) -> String {
    let calendar = Calendar.current
    let day = calendar.component(.day, from: date)
    let month = calendar.component(.month, from: date)
    let template = DateFormatter.dateFormat(fromTemplate: "Md", options: 0, locale: .current) ?? "d/M"
    if let dRange = template.range(of: "d"), let mRange = template.range(of: "M"), mRange.lowerBound < dRange.lowerBound {
        return "\(month)/\(day)"
    }
    return "\(day)/\(month)"
}

// MARK: - Timeline row

private struct TimelineConnector: View {
    let isLast: Bool

    var body: some View {
        VStack(spacing: 0) {
            Circle()
                .fill(Color.accentColor)
                .frame(width: 8, height: 8)
            if !isLast {
                Rectangle()
                    .fill(Color(.separator))
                    .frame(width: 1)
            }
        }
    }
}

private struct TimelineCard: View {
    let note: Note
    let onComment: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                if !note.text.isEmpty {
                    Text(note.text)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if let photo = note.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .clipped()
                }
            }

            NoteVoiceMemo(note: note)

            HStack {
                if note.sharedWithFriends {
                    SharedIndicator()
                }
                if note.isPinned {
                    PinIndicator()
                }
                Spacer()
                CommentBubbleButton(
                    ownerUID: note.ownerUID,
                    noteID: note.id.uuidString,
                    isEnabled: note.sharedWithFriends,
                    action: onComment
                )
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator), lineWidth: 1))
        .contentShape(RoundedRectangle(cornerRadius: 24))
        .onTapGesture(perform: onTap)
        .noteActions(note)
    }
}

private struct TimelineRow: View {
    let note: Note
    let isLast: Bool
    let timeColumnWidth: CGFloat
    let onComment: () -> Void
    let onTap: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var time: TimeDisplay { timeDisplay(for: note.createdAt) }

    private var timeLabel: some View {
        VStack(spacing: 0) {
            Text(time.value)
                .font(.caption)
                .fontWeight(.medium)
            if let period = time.period {
                Text(period)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                timeLabel
                TimelineCard(note: note, onComment: onComment, onTap: onTap)
            }
            .padding(.bottom, 16)
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    timeLabel
                    TimelineConnector(isLast: isLast)
                }
                .frame(width: timeColumnWidth)

                TimelineCard(note: note, onComment: onComment, onTap: onTap)
            }
            .padding(.bottom, 16)
        }
    }
}

// MARK: - Friend tiles

private struct FriendTile: View {
    let friend: FirestoreUser
    let sharedNote: FriendNote?
    let loadState: LiveState
    let onRetry: () -> Void
    let onOpenNote: () -> Void
    let onOpenProfile: () -> Void

    private static let tilePadding: CGFloat = 12
    private static let minHitSize: CGFloat = 44

    @ScaledMetric(relativeTo: .caption) private var avatarSize: CGFloat = 24

    // The avatar button is at least 44 by 44 and centred on where the
    // small avatar sits, so its box reaches inside the tile padding.
    private var avatarHitSize: CGFloat { max(Self.minHitSize, avatarSize) }
    private var avatarInset: CGFloat { Self.tilePadding + avatarSize / 2 - avatarHitSize / 2 }

    private var isFailed: Bool { sharedNote == nil && loadState.isFinal && loadState != .loaded }

    var body: some View {
        if isFailed {
            failedTile
        } else {
            loadedTile
        }
    }

    // A load that failed says so and offers Retry. It never reads as
    // "Nothing shared yet", since that would be a guess.
    private var failedTile: some View {
        VStack(spacing: 8) {
            AvatarView(user: friend, size: 40)
            Text(friend.shownName)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
            Text(loadState.message ?? "Couldn\u{2019}t load")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
        }
        .padding(Self.tilePadding)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Open profile", onOpenProfile)
    }

    private var loadedTile: some View {
        // The tile button fills the tile. The avatar button sits above it
        // in the ZStack, so a tap on the avatar never also opens the note.
        ZStack(alignment: .bottomTrailing) {
            tileButton

            if sharedNote != nil {
                Button(action: onOpenProfile) {
                    AvatarView(user: friend, size: 24, relativeTo: .caption)
                        .frame(minWidth: Self.minHitSize, minHeight: Self.minHitSize)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .padding(.trailing, avatarInset)
                .padding(.bottom, avatarInset)
                // Read once: the tile offers "Open profile" as an action.
                .accessibilityHidden(true)
            }
        }
    }

    private var tileButton: some View {
        Button(action: sharedNote != nil ? onOpenNote : onOpenProfile) {
            Group {
                if let sharedNote {
                    sharedContent(sharedNote)
                } else {
                    emptyContent
                }
            }
            .padding(Self.tilePadding)
            .frame(maxWidth: .infinity, minHeight: 140, alignment: sharedNote != nil ? .topLeading : .center)
            .background(background)
            .overlay(border)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(sharedNote != nil ? "Opens the note" : "Opens their profile")
        .accessibilityAction(named: "Open profile", onOpenProfile)
    }

    @ViewBuilder
    private func sharedContent(_ note: FriendNote) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(shortDateString(note.createdAt))
                Spacer()
                Text(timeString(note.createdAt))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)

            Text(note.text)
                .font(.subheadline)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Spacer()
                Text(friend.shownName)
                    .font(.caption)
                    .fontWeight(.medium)
                    .lineLimit(1)
                // The real avatar is the button layered above the tile.
                Color.clear
                    .frame(width: avatarSize, height: avatarSize)
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: 8) {
            AvatarView(user: friend, size: 40)
            VStack(spacing: 0) {
                Text(friend.shownName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("@\(friend.username)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            Text(loadState == .loading ? "Loading" : "Nothing shared yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: 16)
            .fill(sharedNote != nil ? Color.accentColor.opacity(0.14) : Color(.systemBackground))
    }

    @ViewBuilder
    private var border: some View {
        if sharedNote == nil {
            RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1)
        }
    }

    private var accessibilityLabel: String {
        guard let sharedNote else {
            return loadState == .loading ? "\(friend.shownName), loading" : "\(friend.shownName), nothing shared yet"
        }
        let firstWords = sharedNote.text.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
        let summary = !firstWords.isEmpty ? firstWords
            : sharedNote.hasAudio == true ? "voice memo"
            : sharedNote.hasPhoto ? "photo" : ""
        return "\(friend.shownName), shared \(longDateString(sharedNote.createdAt)) at " +
            "\(timeString(sharedNote.createdAt))" + (summary.isEmpty ? "" : ", \(summary)")
    }
}

#Preview("Light") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type - Large") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Dynamic Type - XXX Large") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Dynamic Type - Accessibility 5") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Sample Data") {
    let _ = UserDefaults.standard.set(true, forKey: "gardenSampleDataEnabled")
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
}

#Preview("Landscape", traits: .landscapeLeft) {
    let _ = UserDefaults.standard.set(true, forKey: "gardenSampleDataEnabled")
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
}
