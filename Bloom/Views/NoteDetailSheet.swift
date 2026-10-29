import SwiftUI
import SwiftData
import Combine
import FirebaseAuth

// What a detail sheet was asked to show: one of my own notes, or a
// note a friend shared with me.
struct NoteDetailRequest: Identifiable {
    enum Kind {
        case mine(Note)
        case friend(FriendNote, ownerUID: String, author: FirestoreUser?)
    }

    let id = UUID()
    let kind: Kind
    // The comment bubble opens the sheet at the comments with the
    // field focused, tapping the rest of a card opens it at the top.
    var focusComments = false

    static func mine(_ note: Note, focusComments: Bool = false) -> NoteDetailRequest {
        NoteDetailRequest(kind: .mine(note), focusComments: focusComments)
    }

    static func friend(
        _ note: FriendNote,
        ownerUID: String,
        author: FirestoreUser?,
        focusComments: Bool = false
    ) -> NoteDetailRequest {
        NoteDetailRequest(kind: .friend(note, ownerUID: ownerUID, author: author), focusComments: focusComments)
    }
}

// The one detail sheet for every tappable note. Owner mode for my own
// posted notes (with the three dot menu), viewer mode for a friend's
// shared note (read only, comments still work). Drafts never open
// here, they open in the composer.
struct NoteDetailSheet: View {
    let request: NoteDetailRequest

    init(request: NoteDetailRequest) {
        self.request = request
    }

    init(note: Note, focusComments: Bool = false) {
        self.request = .mine(note, focusComments: focusComments)
    }

    var body: some View {
        switch request.kind {
        case .mine(let note):
            OwnerNoteDetail(note: note, focusComments: request.focusComments)
        case .friend(let note, let ownerUID, let author):
            ViewerNoteDetail(note: note, ownerUID: ownerUID, author: author, focusComments: request.focusComments)
        }
    }
}

// MARK: - Owner mode

private struct OwnerNoteDetail: View {
    let note: Note
    let focusComments: Bool

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @StateObject private var actions: NoteActionController

    init(note: Note, focusComments: Bool) {
        self.note = note
        self.focusComments = focusComments
        _actions = StateObject(wrappedValue: NoteActionController(note: note))
    }

    private var isGone: Bool { note.isDeleted || note.modelContext == nil }

    var body: some View {
        if isGone {
            // The note was just deleted, the sheet is closing.
            Color.clear
        } else {
            NoteDetailScaffold(
                title: note.createdAt.formatted(date: .abbreviated, time: .shortened),
                ownerUID: note.ownerUID ?? Auth.auth().currentUser?.uid ?? "",
                noteID: note.id.uuidString,
                isOwner: true,
                commentsEnabled: note.sharedWithFriends && !note.isDraft,
                focusComments: focusComments,
                onShare: { actions.requestShareToggle() },
                noteBody: { noteBody },
                menu: { menu }
            )
            .noteActionDialogs(actions)
            .onAppear {
                actions.context = context
                actions.onDeleted = { dismiss() }
            }
        }
    }

    private var menu: some View {
        Menu {
            NoteActionButtons(controller: actions)
        } label: {
            Image(systemName: "ellipsis.circle")
                .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Note options")
    }

    private var noteBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if !note.text.isEmpty {
                Text(note.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let photo = note.photo {
                Image(uiImage: photo)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
                    .accessibilityLabel("Photo")
            }

            NoteVoiceMemo(note: note)

            if let mediaLogEntry = note.mediaLogEntry {
                MediaLogChip(entry: mediaLogEntry)
            }

            statusChips
        }
    }

    // Words as well as icons, so the state never relies on colour.
    private var statusChips: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            chip(
                note.sharedWithFriends ? "Shared with friends" : "Only you",
                systemImage: note.sharedWithFriends ? "person.2.fill" : "lock.fill"
            )
            if note.isPinned {
                chip("Pinned", systemImage: "pin.fill")
            }
        }
    }

    private func chip(_ title: String, systemImage: String) -> some View {
        Label(title, systemImage: systemImage)
            .font(.caption)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }
}

// MARK: - Viewer mode

private struct ViewerNoteDetail: View {
    let note: FriendNote
    let ownerUID: String
    let author: FirestoreUser?
    let focusComments: Bool

    var body: some View {
        NoteDetailScaffold(
            title: note.createdAt.formatted(date: .abbreviated, time: .shortened),
            ownerUID: ownerUID,
            noteID: note.id ?? "",
            isOwner: false,
            commentsEnabled: note.id != nil,
            focusComments: focusComments,
            onShare: nil,
            noteBody: { noteBody },
            menu: { EmptyView() }
        )
    }

    private var noteBody: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let author {
                // Pushes onto the sheet's own stack, so Back returns to the note.
                NavigationLink {
                    FriendProfileView(friend: author)
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(user: author, size: 44, relativeTo: .body)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(author.shownName)
                                .font(.headline)
                            Text("@\(author.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.footnote)
                            .foregroundStyle(.tertiary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens their profile")
            }

            if !note.text.isEmpty {
                Text(note.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // Loaded the same way the friend journal does.
            if note.hasPhoto, let noteID = note.id {
                FriendNotePhoto(friendUID: ownerUID, noteID: noteID)
            }

            FriendVoiceMemo(friendUID: ownerUID, note: note)
        }
    }
}

// MARK: - Shared layout

// One ScrollView with the note on top and the comments below, the
// comment field pinned to the bottom. In landscape the note sits on the
// left and the comments on the right, each scrolling, with the field
// under the comments.
private struct AttachKey: Equatable {
    let ownerUID: String
    let noteID: String
    let enabled: Bool
    let myUID: String?
}

private struct NoteDetailScaffold<NoteBody: View, Menu: View>: View {
    let title: String
    let ownerUID: String
    let noteID: String
    let isOwner: Bool
    let commentsEnabled: Bool
    let focusComments: Bool
    let onShare: (() -> Void)?
    @ViewBuilder let noteBody: () -> NoteBody
    @ViewBuilder let menu: () -> Menu

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var listener = NoteCommentsListener()
    @StateObject private var reactions = NoteReactionsListener()
    @StateObject private var draft = CommentDraft()
    @FocusState private var isInputFocused: Bool

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    // A friend whose note I can no longer read: stopped sharing, or no
    // longer friends. Comments are what tells us, the rules refuse them.
    private var isUnavailable: Bool {
        !isOwner && listener.state == .permissionDenied
    }

    var body: some View {
        NavigationStack {
            Group {
                if isUnavailable {
                    ContentUnavailableView(
                        "You can\u{2019}t see this note",
                        systemImage: "lock",
                        description: Text("It may no longer be shared, or you may no longer be friends.")
                    )
                } else if isCompactHeight {
                    landscapeLayout
                } else {
                    portraitLayout
                }
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                if isOwner {
                    ToolbarItem(placement: .primaryAction) {
                        menu()
                    }
                }
            }
        }
        .onAppear { attach() }
        // Also restarts when the note or account is only known after the
        // first appearance. start() ignores a note that is already running.
        .task(id: AttachKey(ownerUID: ownerUID, noteID: noteID, enabled: commentsEnabled, myUID: Auth.auth().currentUser?.uid)) {
            attach()
        }
        .onDisappear {
            listener.stop()
            reactions.stop()
        }
        .onChange(of: commentsEnabled) { _, _ in attach() }
    }

    // Reactions follow the same rule as comments: shared, posted notes only.
    private func attach() {
        if commentsEnabled, !noteID.isEmpty, !ownerUID.isEmpty {
            listener.start(ownerUID: ownerUID, noteID: noteID)
            reactions.start(ownerUID: ownerUID, noteID: noteID)
        } else {
            listener.stop()
            reactions.stop()
        }
    }

    // MARK: Portrait

    private var portraitLayout: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    noteBody()
                    if commentsEnabled {
                        ReactionsSection(listener: reactions)
                    }
                    CommentsSection(
                        listener: listener,
                        ownerUID: ownerUID,
                        isOwner: isOwner,
                        commentsEnabled: commentsEnabled,
                        onShare: onShare,
                        draft: draft,
                        focusInput: { isInputFocused = true }
                    )
                    .id("comments")
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom) {
                if commentsEnabled {
                    CommentInputBar(listener: listener, draft: draft, isFocused: $isInputFocused)
                }
            }
            .task {
                guard focusComments, commentsEnabled else { return }
                try? await Task.sleep(for: .milliseconds(350))
                withAnimation { proxy.scrollTo("comments", anchor: .top) }
                isInputFocused = true
            }
        }
    }

    // MARK: Landscape

    private var landscapeLayout: some View {
        AnyLayout(HStackLayout(alignment: .top, spacing: 0)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    noteBody()
                    if commentsEnabled {
                        ReactionsSection(listener: reactions)
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            VStack(spacing: 0) {
                ScrollView {
                    CommentsSection(
                        listener: listener,
                        ownerUID: ownerUID,
                        isOwner: isOwner,
                        commentsEnabled: commentsEnabled,
                        onShare: onShare,
                        draft: draft,
                        focusInput: { isInputFocused = true }
                    )
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .scrollDismissesKeyboard(.interactively)

                if commentsEnabled {
                    CommentInputBar(listener: listener, draft: draft, isFocused: $isInputFocused)
                }
            }
        }
        .task {
            guard focusComments, commentsEnabled else { return }
            try? await Task.sleep(for: .milliseconds(350))
            isInputFocused = true
        }
    }
}

// The "Couldn't load" line with a Retry button, shared by the comments
// and reactions sections.
struct LiveFailedNotice: View {
    let text: String
    let retry: () -> Void

    var body: some View {
        HStack {
            Label(text, systemImage: "exclamationmark.triangle")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            Button("Retry", action: retry)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .frame(minHeight: 44)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Comments

private struct CommentsSection: View {
    @ObservedObject var listener: NoteCommentsListener
    let ownerUID: String
    let isOwner: Bool
    let commentsEnabled: Bool
    let onShare: (() -> Void)?
    @ObservedObject var draft: CommentDraft
    let focusInput: () -> Void

    @State private var commentToDelete: NoteComment?
    @State private var errorMessage: String?

    private var myUID: String? { Auth.auth().currentUser?.uid }

    private var heading: String {
        guard commentsEnabled, listener.state == .loaded else { return "Comments" }
        return "Comments \(listener.comments.count)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(heading)
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            if !commentsEnabled {
                disabledState
            } else {
                switch listener.state {
                case .loading:
                    ProgressView("Loading comments")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                case .permissionDenied:
                    notice("You can\u{2019}t see these comments", systemImage: "lock")
                case .missingIndex:
                    notice("Comments aren\u{2019}t available yet", systemImage: "exclamationmark.triangle")
                case .failed:
                    LiveFailedNotice(text: "Couldn\u{2019}t load comments", retry: listener.retry)
                case .loaded where listener.comments.isEmpty:
                    notice("No comments yet", systemImage: "bubble.left")
                case .loaded:
                    ForEach(CommentThread.threads(from: listener.comments)) { thread in
                        CommentThreadView(
                            thread: thread,
                            canDelete: { isOwner || $0.authorUID == myUID },
                            onDelete: { commentToDelete = $0 },
                            onReply: { startReply(to: $0, threadID: $1) }
                        )
                    }
                }
            }

            FormErrorText(message: errorMessage)
        }
        .confirmationDialog(
            "Delete this comment?",
            isPresented: Binding(
                get: { commentToDelete != nil },
                set: { if !$0 { commentToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let comment = commentToDelete { delete(comment) }
                commentToDelete = nil
            }
            Button("Cancel", role: .cancel) { commentToDelete = nil }
        }
    }

    // My own note that isn't shared yet.
    private var disabledState: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Share with friends to let them comment")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let onShare {
                Button("Share with friends", action: onShare)
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
        }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
    }

    // The reply hangs under the top level comment, but is addressed to
    // whoever wrote the comment that was tapped.
    private func startReply(to comment: NoteComment, threadID: String) {
        Task {
            let profile = await UserProfileCache.shared.profile(uid: comment.authorUID)
            draft.startReply(CommentReplyTarget(
                threadID: threadID,
                toUID: comment.authorUID,
                toName: profile?.shownName ?? "Someone",
                mention: profile.map { "@\($0.username) " } ?? ""
            ))
            focusInput()
        }
    }

    private func delete(_ comment: NoteComment) {
        errorMessage = nil
        Task {
            do {
                try await listener.delete(comment)
            } catch {
                errorMessage = "Couldn\u{2019}t delete the comment. Try again."
            }
        }
    }
}

// A top level comment with its replies indented underneath, a thin line
// on their left.
private struct CommentThreadView: View {
    let thread: CommentThread
    let canDelete: (NoteComment) -> Bool
    let onDelete: (NoteComment) -> Void
    let onReply: (NoteComment, _ threadID: String) -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    // Less indent at the largest sizes so the text keeps its width.
    private var indent: CGFloat { dynamicTypeSize.isAccessibilitySize ? 8 : 18 }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            row(thread.top, parentDeleted: thread.parentDeleted)

            if !thread.replies.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(thread.replies) { reply in
                        row(reply, parentDeleted: false)
                    }
                }
                .padding(.leading, 12)
                .overlay(alignment: .leading) {
                    Rectangle()
                        .fill(Color(.separator))
                        .frame(width: 2)
                        .accessibilityHidden(true)
                }
                .padding(.leading, indent)
            }
        }
    }

    private func row(_ comment: NoteComment, parentDeleted: Bool) -> some View {
        CommentRow(
            comment: comment,
            parentDeleted: parentDeleted,
            canDelete: canDelete(comment),
            onDelete: { onDelete(comment) },
            onReply: { onReply(comment, thread.id) }
        )
    }
}

private struct CommentRow: View {
    let comment: NoteComment
    let parentDeleted: Bool
    let canDelete: Bool
    let onDelete: () -> Void
    let onReply: () -> Void

    @State private var author: FirestoreUser?
    @State private var repliedTo: FirestoreUser?

    private var name: String { author?.shownName ?? "Someone" }
    private var repliedToName: String { repliedTo?.shownName ?? "Someone" }

    // The text with a leading @username in bold as well as coloured.
    private var styledText: AttributedString {
        var attributed = AttributedString(comment.text)
        guard comment.isReply, comment.text.hasPrefix("@") else { return attributed }
        let mention = String(comment.text.prefix { !$0.isWhitespace })
        if let range = attributed.range(of: mention) {
            attributed[range].font = .body.bold()
            attributed[range].foregroundColor = .accentColor
        }
        return attributed
    }

    private var spokenText: String {
        var spoken = comment.isReply && comment.replyToUID != nil
            ? "Reply from \(name) to \(repliedToName): \(comment.text)"
            : "\(name): \(comment.text)"
        if parentDeleted { spoken += ". In reply to a deleted comment" }
        return spoken
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            AvatarView(
                uid: comment.authorUID,
                name: name,
                hasAvatar: author?.hasAvatar ?? false,
                avatarUpdatedAt: author?.avatarUpdatedAt,
                size: comment.isReply && !parentDeleted ? 28 : 36,
                relativeTo: .body
            )
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(name)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        Text(comment.createdAt, format: .relative(presentation: .named))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if parentDeleted {
                        Text("In reply to a deleted comment")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(styledText)
                        .font(.body)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spokenText)

                Button(action: onReply) {
                    Text("Reply")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Reply to \(name)")
            }

            if canDelete {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Delete comment by \(name)")
            }
        }
        .task(id: comment.authorUID) {
            author = await UserProfileCache.shared.profile(uid: comment.authorUID)
        }
        .task(id: comment.replyToUID) {
            guard let uid = comment.replyToUID else { return }
            repliedTo = await UserProfileCache.shared.profile(uid: uid)
        }
    }
}

// The field pinned to the bottom: one to four lines, a counter as the
// text nears 500 characters, and Send. A failed send puts the text back.
private struct CommentInputBar: View {
    @ObservedObject var listener: NoteCommentsListener
    @ObservedObject var draft: CommentDraft
    var isFocused: FocusState<Bool>.Binding

    @State private var errorMessage: String?

    private var text: String { draft.text }
    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    // A reply that is only the prefilled @username says nothing yet.
    private var canSend: Bool {
        guard !trimmed.isEmpty else { return false }
        if let reply = draft.reply, !reply.mention.isEmpty, text == reply.mention { return false }
        return true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let reply = draft.reply {
                HStack(spacing: 8) {
                    Text("Replying to \(reply.toName)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Replying to \(reply.toName)")
                    Button {
                        draft.cancelReply()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("Cancel reply")
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                TextField("Add a comment", text: $draft.text, axis: .vertical)
                    .lineLimit(1...4)
                    .focused(isFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 18))
                    .accessibilityLabel("Add a comment")

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .frame(minWidth: 44, minHeight: 44)
                }
                .disabled(!canSend)
                .accessibilityLabel("Send comment")
            }

            if text.count >= NoteComment.maxLength - 100 {
                Text("\(text.count) of \(NoteComment.maxLength)")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(text.count >= NoteComment.maxLength ? .red : .secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityLabel("\(text.count) of \(NoteComment.maxLength) characters used")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        // Cut by whole characters so an emoji is never split.
        .onChange(of: draft.text) { _, newValue in
            if newValue.count > NoteComment.maxLength {
                draft.text = String(newValue.prefix(NoteComment.maxLength))
            }
        }
    }

    private func send() {
        guard canSend, let uid = Auth.auth().currentUser?.uid else { return }
        let sending = text
        let sendingReply = draft.reply
        draft.text = ""
        draft.clearReply()
        errorMessage = nil
        Task {
            do {
                try await listener.send(sending, authorUID: uid, replyTo: sendingReply)
            } catch {
                if draft.text.isEmpty {
                    draft.text = sending
                    if draft.reply == nil { draft.restoreReply(sendingReply) }
                }
                errorMessage = "Couldn\u{2019}t send your comment. Try again."
            }
        }
    }
}

// The text in the comment field and who it replies to, shared by the
// Reply buttons in the list and the field at the bottom.
@MainActor
private final class CommentDraft: ObservableObject {
    @Published var text = ""
    @Published private(set) var reply: CommentReplyTarget?

    // Fills the field with the mention. An empty field or one that still
    // starts with the previous mention swaps it, anything else gets the
    // mention put in front of what was typed.
    func startReply(_ target: CommentReplyTarget) {
        if let old = reply?.mention, !old.isEmpty, text.hasPrefix(old) {
            text = target.mention + text.dropFirst(old.count)
        } else if text.isEmpty {
            text = target.mention
        } else if !target.mention.isEmpty {
            text = target.mention + text
        }
        reply = target
        AccessibilityNotification.Announcement("Replying to \(target.toName)").post()
    }

    // Removes the mention only while it is still exactly what was prefilled.
    func cancelReply() {
        if let reply, !reply.mention.isEmpty, text == reply.mention { text = "" }
        reply = nil
    }

    func clearReply() { reply = nil }

    func restoreReply(_ target: CommentReplyTarget?) { reply = target }
}
