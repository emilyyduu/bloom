import SwiftUI
import SwiftData
import Combine
import FirebaseAuth

// Half typed comments, one per note id, kept while the screen is open so
// swiping to another card and back never loses what was typed.
@MainActor
private final class CommentDraftStore: ObservableObject {
    private var drafts: [UUID: CommentDraft] = [:]

    func draft(for noteID: UUID) -> CommentDraft {
        if let existing = drafts[noteID] { return existing }
        let created = CommentDraft()
        drafts[noteID] = created
        return created
    }

    // Notes that are gone take their draft with them.
    func keepOnly(_ noteIDs: [UUID]) {
        let keep = Set(noteIDs)
        drafts = drafts.filter { keep.contains($0.key) }
    }
}

// Today's posted notes as swipeable cards, oldest to newest, opening on
// the most recent. The neighbouring cards peek in at the edges so it is
// clear they can be swiped. Drafts never appear.
struct TodaysNotesView: View {
    @Query(Note.todaysNotesDescriptor()) private var todaysNotes: [Note]

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedID: UUID?
    @State private var isShowingComposer = false
    @State private var detail: NoteDetailRequest?
    @State private var reactorsListener: NoteReactionsListener?
    @StateObject private var draftStore = CommentDraftStore()

    private static let cardWidthFraction: CGFloat = 0.9

    private var ids: [UUID] { todaysNotes.map(\.id) }

    // What is showing: the scroll position if that note still exists,
    // otherwise the newest.
    private var currentID: UUID? {
        if let selectedID, ids.contains(selectedID) { return selectedID }
        return ids.last
    }

    private var currentIndex: Int? {
        currentID.flatMap { ids.firstIndex(of: $0) }
    }

    var body: some View {
        Group {
            if todaysNotes.isEmpty {
                emptyState
            } else {
                carousel
            }
        }
        .sheet(isPresented: $isShowingComposer) {
            NoteComposerView()
        }
        .sheet(item: $detail) { NoteDetailSheet(request: $0) }
        .sheet(isPresented: Binding(
            get: { reactorsListener != nil },
            set: { if !$0 { reactorsListener = nil } }
        )) {
            if let reactorsListener { ReactorsSheet(listener: reactorsListener) }
        }
    }

    private var emptyState: some View {
        // Built by hand rather than ContentUnavailableView, which shrinks
        // its button to the label. The button fills the width instead.
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "note.text")
                    .textStyle(.display)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text("No notes today")
                    .textStyle(.heading)
                Text("Notes you add today will appear here.")
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            Button("Add note") { isShowingComposer = true }
                .buttonStyle(.bloomPrimary)
        }
        .padding(.horizontal, Theme.Spacing.screenEdge)
        .frame(maxWidth: 400)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Carousel

    private var carousel: some View {
        VStack(spacing: Theme.Spacing.sm) {
            positionRow

            GeometryReader { proxy in
                ScrollView(.horizontal) {
                    LazyHStack(spacing: Theme.Spacing.sm) {
                        ForEach(todaysNotes) { note in
                            TodaysNoteCard(
                                note: note,
                                isSelected: note.id == currentID,
                                draft: draftStore.draft(for: note.id),
                                onOpenDetail: { detail = $0 },
                                onShowReactors: { reactorsListener = $0 }
                            )
                            // The space between the side margins, which is
                            // about 90 percent of the width, so the next
                            // card peeks in, and the full height.
                            .containerRelativeFrame([.horizontal, .vertical])
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID)
                // Equal space on both sides, so the card in view is centred,
                // including the first and the last.
                .contentMargins(.horizontal, proxy.size.width * (1 - Self.cardWidthFraction) / 2, for: .scrollContent)
                .defaultScrollAnchor(.trailing)
                .scrollIndicators(.hidden)
            }
            // 16 points under the cards, the tab bar sits below that.
            .padding(.bottom, Theme.Spacing.lg)
        }
        .onAppear {
            if selectedID == nil { selectedID = ids.last }
        }
        .onChange(of: ids) { oldIDs, newIDs in
            draftStore.keepOnly(newIDs)
            if let added = newIDs.last, newIDs.count > oldIDs.count, !oldIDs.contains(added) {
                // A new note jumps to it.
                withAnimation(reduceMotion ? nil : .default) { selectedID = added }
            } else if let selectedID, !newIDs.contains(selectedID) {
                // The card showing was deleted: the one that took its place,
                // or the one before it when it was the last.
                let oldIndex = oldIDs.firstIndex(of: selectedID) ?? newIDs.count
                let neighbour = newIDs.indices.contains(oldIndex) ? newIDs[oldIndex] : newIDs.last
                withAnimation(reduceMotion ? nil : .default) { self.selectedID = neighbour }
            }
            // Otherwise other notes changed, and the selection stays.
        }
    }

    // "3 of 5" with previous and next buttons for VoiceOver and keyboards.
    private var positionRow: some View {
        HStack {
            stepButton(systemImage: "chevron.left", label: "Previous note", delta: -1)
                .keyboardShortcut(.leftArrow, modifiers: .command)

            Spacer(minLength: 0)

            if let index = currentIndex {
                Text("\(index + 1) of \(ids.count)")
                    .textStyle(.callout)
                    .fontWeight(.medium)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityLabel("Note \(index + 1) of \(ids.count)")
            }

            Spacer(minLength: 0)

            stepButton(systemImage: "chevron.right", label: "Next note", delta: 1)
                .keyboardShortcut(.rightArrow, modifiers: .command)
        }
        .padding(.horizontal, Theme.Spacing.lg)
    }

    private func stepButton(systemImage: String, label: String, delta: Int) -> some View {
        let target = currentIndex.map { $0 + delta }
        let isEnabled = target.map { ids.indices.contains($0) } ?? false
        return Button {
            guard let target, ids.indices.contains(target) else { return }
            withAnimation(reduceMotion ? nil : .default) { selectedID = ids[target] }
        } label: {
            Image(systemName: systemImage)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}

// MARK: - Card

private struct LiveKey: Equatable {
    let noteID: String
    let isAttached: Bool
}

private struct TodaysNoteCard: View {
    let note: Note
    let isSelected: Bool
    @ObservedObject var draft: CommentDraft
    // The carousel presents the detail and reactors sheets, so they don't
    // depend on a card inside a lazy scroll view staying put.
    let onOpenDetail: (NoteDetailRequest) -> Void
    let onShowReactors: (NoteReactionsListener) -> Void

    @Environment(\.modelContext) private var context
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var actions: NoteActionController
    @StateObject private var quick: NoteQuickAttach
    // Only attached while this card is the selected one.
    @StateObject private var comments = NoteCommentsListener()
    @StateObject private var reactions = NoteReactionsListener()
    @ObservedObject private var commentCounts = CommentCounts.shared
    @ObservedObject private var blocks = BlockService.shared
    @ObservedObject private var reactionCounts = ReactionCounts.shared
    @FocusState private var isInputFocused: Bool
    // Below this card height (a small iPhone) only the latest comment shows.
    @ScaledMetric(relativeTo: .body) private var tightHeight: CGFloat = 520

    init(
        note: Note,
        isSelected: Bool,
        draft: CommentDraft,
        onOpenDetail: @escaping (NoteDetailRequest) -> Void,
        onShowReactors: @escaping (NoteReactionsListener) -> Void
    ) {
        self.note = note
        self.isSelected = isSelected
        self.draft = draft
        self.onOpenDetail = onOpenDetail
        self.onShowReactors = onShowReactors
        _actions = StateObject(wrappedValue: NoteActionController(note: note))
        _quick = StateObject(wrappedValue: NoteQuickAttach(note: note))
    }

    private var isGone: Bool { note.isDeleted || note.modelContext == nil }
    private var isCompactHeight: Bool { verticalSizeClass == .compact }
    private var noteID: String { note.id.uuidString }
    private var ownerUID: String { note.ownerUID ?? Auth.auth().currentUser?.uid ?? "" }
    // Only shared, posted notes have comments and reactions.
    private var isShared: Bool { note.sharedWithFriends && !note.isDraft }
    private var canAttach: Bool { isShared && !ownerUID.isEmpty }

    var body: some View {
        if isGone {
            // Just deleted, the carousel is moving to a neighbour.
            Color.clear
        } else {
            GeometryReader { proxy in
                layout(cardHeight: proxy.size.height)
            }
            .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.Colors.surfaceMuted))
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
            .accessibilityElement(children: .contain)
            .noteActionDialogs(actions)
            .quickAttachPresentations(quick)
            .onAppear { actions.context = context }
            // Comments and reactions are live only for the selected card,
            // the others show lazily loaded counts.
            .task(id: LiveKey(noteID: noteID, isAttached: isSelected && canAttach)) {
                if isSelected && canAttach {
                    comments.start(ownerUID: ownerUID, noteID: noteID)
                    reactions.start(ownerUID: ownerUID, noteID: noteID)
                } else {
                    comments.stop()
                    reactions.stop()
                }
            }
            .task(id: noteID) {
                guard canAttach else { return }
                await commentCounts.ensure(ownerUID: ownerUID, noteID: noteID)
                await reactionCounts.ensure(ownerUID: ownerUID, noteID: noteID)
            }
            .onDisappear {
                comments.stop()
                reactions.stop()
            }
        }
    }

    @ViewBuilder
    private func layout(cardHeight: CGFloat) -> some View {
        if isCompactHeight {
            landscapeLayout(cardHeight: cardHeight)
        } else if dynamicTypeSize.isAccessibilitySize {
            // The footer isn't pinned at these sizes, it scrolls with the note.
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                    header
                    content(cardHeight: cardHeight)
                    footer(isTight: true)
                }
                .padding(Theme.Spacing.lg)
            }
            .scrollDismissesKeyboard(.interactively)
        } else {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        content(cardHeight: cardHeight)
                    }
                    .padding(Theme.Spacing.lg)
                }
                footer(isTight: cardHeight < tightHeight)
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.sm)
            }
        }
    }

    // MARK: Landscape

    // The note and its icon row on the left, reactions and comments on
    // the right, each scrolling.
    private func landscapeLayout(cardHeight: CGFloat) -> some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                        header
                        content(cardHeight: cardHeight)
                    }
                    .padding(Theme.Spacing.lg)
                }
                toolsRow
                    .padding(.horizontal, Theme.Spacing.lg)
                    .padding(.bottom, Theme.Spacing.sm)
            }
            .frame(maxWidth: .infinity)

            Divider()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        if !isShared {
                            onlyYouBlock
                        } else if isSelected {
                            ReactionsSection(listener: reactions, isCompact: true, onShowReactors: { onShowReactors(reactions) })
                            commentsHeader
                            commentsList(limit: nil)
                        } else {
                            countsBlock
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Theme.Spacing.lg)
                }
                .scrollDismissesKeyboard(.interactively)

                if isShared && isSelected {
                    inputBar
                        .padding(.horizontal, Theme.Spacing.lg)
                        .padding(.bottom, Theme.Spacing.sm)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: Header and content

    private var dateText: String {
        let day = note.createdAt.formatted(.dateTime.weekday(.wide).day().month(.wide))
        let time = note.createdAt.formatted(date: .omitted, time: .shortened)
        return "\(day), \(time)"
    }

    // The date and time, the sharing chip, a pin if pinned, and the menu.
    private var header: some View {
        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
            VStack(alignment: .leading, spacing: 6) {
                Text(dateText)
                    .textStyle(.subheading)
                HStack(spacing: Theme.Spacing.sm) {
                    Label(
                        note.sharedWithFriends ? "Shared with friends" : "Only you",
                        systemImage: note.sharedWithFriends ? "person.2.fill" : "lock.fill"
                    )
                    .textStyle(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Theme.Colors.surfaceMuted, in: Capsule())

                    if note.isPinned { PinIndicator() }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Menu {
                NoteActionButtons(controller: actions)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .frame(minWidth: 44, minHeight: 44)
            }
            .accessibilityLabel("Note options")
        }
    }

    // The text, photo, voice memo and media chip. Pressing and holding
    // an attachment offers Remove, with a matching VoiceOver action.
    private func content(cardHeight: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
            if !note.text.isEmpty {
                Text(note.text)
                    .textStyle(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let photo = note.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFill()
                    .frame(maxWidth: .infinity, maxHeight: cardHeight * 0.4)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    .accessibilityLabel("Photo")
                    .contextMenu {
                        Button("Remove photo", systemImage: "trash", role: .destructive) { quick.removePhoto() }
                    }
                    .accessibilityAction(named: Text("Remove photo")) { quick.removePhoto() }
            }

            if note.hasAudio {
                NoteVoiceMemo(note: note)
                    .contextMenu {
                        Button("Remove voice memo", systemImage: "trash", role: .destructive) { quick.removeMemo() }
                    }
                    .accessibilityAction(named: Text("Remove voice memo")) { quick.removeMemo() }
            }

            if let entry = note.mediaLogEntry {
                MediaLogChip(entry: entry)
                    .contextMenu {
                        Button("Remove movie or show", systemImage: "trash", role: .destructive) { quick.removeMedia() }
                    }
                    .accessibilityAction(named: Text("Remove movie or show")) { quick.removeMedia() }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpenDetail(.mine(note)) }
        .accessibilityAction(named: Text("Open note details")) { onOpenDetail(.mine(note)) }
    }

    // MARK: Footer

    // The icon row, then reactions and comments (or "Only you"). With the
    // keyboard up on a short card the icon row and reactions step aside, so
    // the comment being typed keeps its room.
    private func footer(isTight: Bool) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if !isInputFocused {
                toolsRow
            }

            if !isShared {
                onlyYouBlock
            } else if isSelected {
                if !isInputFocused {
                    ReactionsSection(listener: reactions, isCompact: true, onShowReactors: { onShowReactors(reactions) })
                }
                commentsHeader
                // Just the latest comment, so the note keeps the room.
                // "View all comments" opens the rest.
                commentsList(limit: 1)
                inputBar
            } else {
                countsBlock
            }
        }
    }

    private var toolsRow: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            if let notice = quick.notice {
                CameraNoticeRow(notice: notice) { quick.notice = nil }
            }
            NoteToolsBar(
                hasPhoto: note.hasPhoto,
                hasVoiceMemo: note.hasAudio,
                hasMedia: note.mediaLogEntry != nil,
                onTakePhoto: { quick.takePhoto() },
                onChoosePhoto: { quick.choosePhoto() },
                onVoiceMemo: { quick.recordMemo() },
                onMedia: { quick.openMedia() },
                style: .compact
            )
        }
    }

    private var onlyYouBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Label("Only you", systemImage: "lock.fill")
                .textStyle(.subheading)
            Button("Share with friends") { actions.requestShareToggle() }
                .buttonStyle(.bloomSecondary)
        }
    }

    // What a card that isn't selected shows: counts only.
    private var countsBlock: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(reactionCounts.count(ownerUID: ownerUID, noteID: noteID).map { "Reactions (\($0))" } ?? "Reactions")
                .textStyle(.subheading)
            Text(commentCounts.count(ownerUID: ownerUID, noteID: noteID).map { "Comments (\($0))" } ?? "Comments")
                .textStyle(.subheading)
            viewAllButton
        }
    }

    private var commentsHeader: some View {
        HStack {
            Text(commentsTitle)
                .textStyle(.subheading)
                .accessibilityAddTraits(.isHeader)
            Spacer(minLength: 8)
            viewAllButton
        }
    }

    private var commentsTitle: String {
        let count = comments.state == .loaded
            ? comments.comments.count
            : commentCounts.count(ownerUID: ownerUID, noteID: noteID)
        return count.map { "Comments (\($0))" } ?? "Comments"
    }

    private var viewAllButton: some View {
        Button("View all comments") {
            onOpenDetail(.mine(note, scrollToComments: true))
        }
        .textStyle(.callout)
        .frame(minHeight: 44)
    }

    // The latest comments, each with Reply. nil shows every comment.
    @ViewBuilder
    private func commentsList(limit: Int?) -> some View {
        switch comments.state {
        case .loading:
            ProgressView("Loading comments")
                .frame(maxWidth: .infinity)
        case .permissionDenied:
            notice("You can\u{2019}t see these comments", systemImage: "lock")
        case .missingIndex:
            notice("Comments aren\u{2019}t available yet", systemImage: "exclamationmark.triangle")
        case .failed:
            LiveFailedNotice(text: "Couldn\u{2019}t load comments", retry: { comments.retry() })
        case .loaded where comments.visibleComments.isEmpty:
            notice("No comments yet", systemImage: "bubble.left")
        case .loaded:
            let sorted = comments.visibleComments.sorted { ($0.createdAt, $0.id) < ($1.createdAt, $1.id) }
            let shown = limit.map { Array(sorted.suffix($0)) } ?? sorted
            ForEach(shown) { comment in
                CommentRow(
                    comment: comment,
                    parentDeleted: false,
                    canDelete: false,
                    onDelete: {},
                    onReply: { startReply(to: comment) },
                    moderationContext: (ownerUID, noteID)
                )
            }
        }
    }

    private var inputBar: some View {
        CommentInputBar(listener: comments, draft: draft, isFocused: $isInputFocused, isEmbedded: true)
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .textStyle(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func startReply(to comment: NoteComment) {
        Task {
            await draft.startReply(to: comment, threadID: comment.replyToCommentId ?? comment.id)
            isInputFocused = true
        }
    }
}

#Preview {
    NavigationStack {
        TodaysNotesView()
    }
    .modelContainer(PreviewContainer.shared)
}
