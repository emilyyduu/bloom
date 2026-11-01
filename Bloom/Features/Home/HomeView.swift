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
    @StateObject private var circleStore = CircleStore.shared

    @State private var isShowingComposer = false
    @State private var isShowingAddFriend = false
    @State private var isShowingNotifications = false
    @State private var noteDetail: NoteDetailRequest?
    @State private var selectedFriendForJournal: FirestoreUser?
    @State private var isOnScreen = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.scenePhase) private var scenePhase
    @ScaledMetric(relativeTo: .body) private var minFriendTileWidth: CGFloat = 150

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    // In landscape on iPhone (compact height), the timeline and Friends
    // sit side by side instead of one above the other, but both stay
    // inside the one ScrollView so scroll position survives rotation.
    private var columnsLayout: AnyLayout {
        isCompactHeight
            ? AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.xl))
            : AnyLayout(VStackLayout(spacing: Theme.Spacing.xxl))
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

    // Every friend, before any circle filter.
    private var allFriends: [FirestoreUser] { friendService.friends }

    // The tiles shown: everyone, or only the members of the chosen circle.
    private var displayedFriends: [FirestoreUser] {
        guard let circle = circleStore.homeFilterCircle else { return allFriends }
        return circleStore.members(of: circle, among: allFriends)
    }

    private func loadState(for friend: FirestoreUser) -> LiveState {
        guard let id = friend.id else { return .loaded }
        return friendJournalService.loadState(for: id)
    }

    private var displayedLatestNoteByFriend: [String: FriendNote] {
        friendJournalService.latestNoteByFriend
    }

    // The friends whose tiles get a live listener, scoped to the friends
    // actually shown here rather than any broader list.
    private var friendUIDsForTileRefresh: [String] {
        displayedFriends.compactMap(\.id)
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
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.md)

                ScrollView {
                    columnsLayout {
                        timelineSection
                            .frame(maxWidth: isCompactHeight ? 360 : .infinity, alignment: .leading)
                        friendsSection
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.xl)
                }
                .refreshable {
                    friendJournalService.syncListeners(for: friendUIDsForTileRefresh)
                    await friendJournalService.refreshLatestNotes(for: friendUIDsForTileRefresh)
                }
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .background(Theme.Colors.background)
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
                circleStore.startListening()
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
            // Midnight while Home is open: syncListeners notices the new
            // day and restarts every tile for it.
            .task {
                for await _ in NotificationCenter.default.notifications(named: .NSCalendarDayChanged) {
                    guard isOnScreen else { continue }
                    friendJournalService.syncListeners(for: friendUIDsForTileRefresh)
                }
            }
        }
    }

    private var bellButton: some View {
        Button {
            isShowingNotifications = true
        } label: {
            Image(systemName: "bell")
        }
        .buttonStyle(.bloomCircle)
        // The badge sits on the circle's corner, outside the button label, so
        // large text sizes can't push it over the bell. The circle is a fixed
        // 44pt, so the badge text is capped rather than allowed to grow with it.
        .overlay(alignment: .topTrailing) {
            if unseenCount > 0 {
                Text(unseenCount > 9 ? "9+" : "\(unseenCount)")
                    .textStyle(.label)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .lineLimit(1)
                    .foregroundStyle(Theme.Colors.textOnColor)
                    .padding(.horizontal, Theme.Spacing.xs)
                    .background(Theme.Palette.red, in: Capsule())
                    .offset(x: Theme.Spacing.xs, y: -Theme.Spacing.xs)
                    .allowsHitTesting(false)
            }
        }
        .accessibilityLabel("Notifications")
        .accessibilityValue(unseenCount > 0 ? "\(unseenCount) new" : "")
    }

    private var streakLine: some View {
        Button {
            selectedTab = .greenhouse
        } label: {
            Text("Streaks: \(currentStreak) day\(currentStreak == 1 ? "" : "s")")
                .textStyle(.callout)
                .fontWeight(.semibold)
                .foregroundStyle(Theme.Colors.textSecondary)
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
                    TimelineRow(date: note.createdAt, isLast: index == todaysNotes.count - 1) {
                        NoteTimelineCard(
                            note: note,
                            onComment: { noteDetail = .mine(note, focusComments: true) },
                            onTap: { noteDetail = .mine(note) }
                        )
                    }
                }
            }
        }
    }

    private var emptyTimelineState: some View {
        VStack(spacing: Theme.Spacing.md) {
            Text("What’s happening?")
                .textStyle(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Add Note") {
                isShowingComposer = true
            }
            .buttonStyle(.bloomPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }

    // MARK: - Friends

    private var friendsSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            SectionHeader("Friends’ notes today")
                .accessibilityAddTraits(.isHeader)

            if allFriends.isEmpty {
                emptyFriendsState
            } else {
                if !circleStore.circles.isEmpty {
                    circleChips
                }
                if displayedFriends.isEmpty {
                    Text("No friends in \(circleStore.homeFilterCircle?.name ?? "this circle") yet")
                        .textStyle(.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Theme.Spacing.lg)
                } else {
                    friendsGrid
                }
            }
        }
    }

    // All, then one chip per circle. The chosen chip has a checkmark and a
    // heavier weight as well as a tint. Saved per account.
    private var circleChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                FilterChip(title: "All", isSelected: circleStore.homeFilterCircle == nil) {
                    circleStore.selectHomeFilter(nil)
                }
                ForEach(circleStore.circles) { circle in
                    FilterChip(title: circle.name, isSelected: circleStore.homeFilterCircleID == circle.id) {
                        circleStore.selectHomeFilter(circle.id)
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .accessibilityLabel("Filter friends")
    }

    private var friendsGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: minFriendTileWidth), spacing: Theme.Spacing.md)], spacing: Theme.Spacing.md) {
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
        VStack(spacing: Theme.Spacing.md) {
            Text("Add friends to see what they share")
                .textStyle(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
            Button("Add Friend") {
                isShowingAddFriend = true
            }
            .buttonStyle(.bloomPrimary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.lg)
    }
}

// MARK: - Supporting types

private struct TileListenerKey: Equatable {
    let uid: String?
    let friendUIDs: [String]
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.xs) {
                if isSelected {
                    Image(systemName: "checkmark")
                        .textStyle(.label)
                        .accessibilityHidden(true)
                }
                Text(title)
                    .textStyle(.callout)
                    .fontWeight(isSelected ? .bold : .regular)
                    .lineLimit(1)
            }
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(minHeight: 44)
            .background(
                Capsule().fill(isSelected ? Theme.Palette.greenTint : Theme.Colors.surfaceMuted)
            )
            .overlay(
                Capsule().strokeBorder(isSelected ? Theme.Colors.actionFill : Color.clear, lineWidth: 1.5)
            )
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct FriendTileItem: Identifiable {
    let id: String
    let friend: FirestoreUser
    let note: FriendNote?
    let loadState: LiveState
}

// MARK: - Date and time helpers

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

// MARK: - Friend tiles

private struct FriendTile: View {
    let friend: FirestoreUser
    let sharedNote: FriendNote?
    let loadState: LiveState
    let onRetry: () -> Void
    let onOpenNote: () -> Void
    let onOpenProfile: () -> Void

    private static let tilePadding: CGFloat = Theme.Spacing.md
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
    // "Nothing shared today", since that would be a guess.
    private var failedTile: some View {
        VStack(spacing: Theme.Spacing.sm) {
            AvatarView(user: friend, size: 40)
            Text(friend.shownName)
                .textStyle(.callout)
                .multilineTextAlignment(.center)
            Text(loadState.message ?? "Couldn\u{2019}t load")
                .textStyle(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button("Retry", action: onRetry)
                .buttonStyle(.bloomSecondary)
        }
        .padding(Self.tilePadding)
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(background)
        .overlay(border)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
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
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(sharedNote != nil ? "Opens the note" : "Opens their profile")
        .accessibilityAction(named: "Open profile", onOpenProfile)
    }

    @ViewBuilder
    private func sharedContent(_ note: FriendNote) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            // Always from today, so the time is enough.
            Text(timeString(note.createdAt))
                .textStyle(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)

            Text(note.text)
                .textStyle(.callout)
                .lineLimit(4)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            HStack(spacing: Theme.Spacing.xs) {
                Spacer()
                Text(friend.shownName)
                    .textStyle(.caption)
                    .lineLimit(1)
                // The real avatar is the button layered above the tile.
                Color.clear
                    .frame(width: avatarSize, height: avatarSize)
            }
        }
    }

    private var emptyContent: some View {
        VStack(spacing: Theme.Spacing.sm) {
            AvatarView(user: friend, size: 40)
            VStack(spacing: 0) {
                Text(friend.shownName)
                    .textStyle(.callout)
                Text("@\(friend.username)")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            Text(loadState == .loading ? "Loading" : "Nothing shared today")
                .textStyle(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    private var background: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
            .fill(sharedNote != nil ? Theme.Palette.greenTint : Theme.Colors.surface)
    }

    @ViewBuilder
    private var border: some View {
        if sharedNote == nil {
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .strokeBorder(Theme.Colors.separator, lineWidth: 1)
        }
    }

    private var accessibilityLabel: String {
        guard let sharedNote else {
            return loadState == .loading ? "\(friend.shownName), loading" : "\(friend.shownName), nothing shared today"
        }
        let firstWords = sharedNote.text.split(whereSeparator: \.isWhitespace).prefix(8).joined(separator: " ")
        let summary = !firstWords.isEmpty ? firstWords
            : sharedNote.hasAudio == true ? "voice memo"
            : sharedNote.hasPhoto ? "photo" : ""
        return "\(friend.shownName), shared today at " +
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

#Preview("Landscape", traits: .landscapeLeft) {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
}
