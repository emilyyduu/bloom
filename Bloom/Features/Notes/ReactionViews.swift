import SwiftUI
import FirebaseAuth

// The Reactions row of the note detail sheet: the six reactions with
// their counts, my choice ringed, and a link to who reacted. Only shared,
// posted notes have reactions, so the sheet leaves this out otherwise.
struct ReactionsSection: View {
    @ObservedObject var listener: NoteReactionsListener
    // On a Today's Notes card the heading is left out to save height.
    var isCompact = false
    // When set, the host presents the reactors sheet itself. A card that
    // already presents other sheets does that, as a sheet from inside the
    // card didn't open.
    var onShowReactors: (() -> Void)? = nil

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingReactors = false

    private var myUID: String? { Auth.auth().currentUser?.uid }
    private var myReaction: ReactionKind? { listener.myReaction(uid: myUID) }

    // Six across normally, two rows of three at large text sizes.
    private var columns: [GridItem] {
        let count = dynamicTypeSize >= .xxxLarge ? 3 : 6
        return Array(repeating: GridItem(.flexible(), spacing: Theme.Spacing.sm), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? Theme.Spacing.xs : Theme.Spacing.md) {
            if !isCompact {
                Text("Reactions")
                    .textStyle(.subheading)
                    .accessibilityAddTraits(.isHeader)
            }

            switch listener.state {
            case .loading:
                ProgressView("Loading reactions")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, Theme.Spacing.lg)
            case .permissionDenied:
                notice("You can\u{2019}t see these reactions", systemImage: "lock")
            case .missingIndex:
                notice("Reactions aren\u{2019}t available yet", systemImage: "exclamationmark.triangle")
            case .failed:
                LiveFailedNotice(text: "Couldn\u{2019}t load reactions", retry: listener.retry)
            case .loaded:
                LazyVGrid(columns: columns, spacing: Theme.Spacing.sm) {
                    ForEach(ReactionKind.allCases) { kind in
                        ReactionButton(
                            kind: kind,
                            count: listener.count(for: kind),
                            isSelected: myReaction == kind
                        ) {
                            react(kind)
                        }
                    }
                }

                if !listener.reactions.isEmpty {
                    Button("See who reacted") {
                        if let onShowReactors { onShowReactors() } else { isShowingReactors = true }
                    }
                        .textStyle(.callout)
                        .frame(minHeight: 44)
                }
            }

            FormErrorText(message: listener.errorMessage)
        }
        .sheet(isPresented: $isShowingReactors) {
            ReactorsSheet(listener: listener)
        }
    }

    private func react(_ kind: ReactionKind) {
        guard let uid = myUID else { return }
        Task { await listener.toggle(kind, myUID: uid) }
    }

    private func notice(_ text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .textStyle(.callout)
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Theme.Spacing.sm)
    }
}

// One reaction: the emoji over its count. My choice has a ring and a
// heavier count as well as a tint, and the selected trait for VoiceOver.
private struct ReactionButton: View {
    let kind: ReactionKind
    let count: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 2) {
                Text(kind.emoji)
                    .textStyle(.heading)
                Text("\(count)")
                    .textStyle(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Theme.Colors.textPrimary : Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous)
                    .fill(isSelected ? Theme.Palette.greenTint : Theme.Colors.surfaceMuted)
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous).strokeBorder(Theme.Colors.actionFill, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title), \(count) \(count == 1 ? "reaction" : "reactions")")
        .accessibilityHint(isSelected ? "Removes your reaction" : "Reacts with \(kind.title.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// Who reacted and with what, newest first. Reads the same live listener
// as the row, so it stays current while open.
struct ReactorsSheet: View {
    @ObservedObject var listener: NoteReactionsListener

    @Environment(\.dismiss) private var dismiss

    private var sorted: [NoteReaction] {
        listener.reactions.sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        NavigationStack {
            Group {
                if sorted.isEmpty {
                    ContentUnavailableView("No reactions yet", systemImage: "face.smiling")
                } else {
                    List(sorted) { reaction in
                        ReactorRow(reaction: reaction)
                    }
                    .scrollContentBackground(.hidden)
                    .background(Theme.Colors.background)
                }
            }
            .navigationTitle("Reactions")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ReactorRow: View {
    let reaction: NoteReaction

    @State private var author: FirestoreUser?

    private var name: String { author?.shownName ?? "Someone" }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            AvatarView(
                uid: reaction.id,
                name: name,
                hasAvatar: author?.hasAvatar ?? false,
                avatarUpdatedAt: author?.avatarUpdatedAt,
                size: 40,
                relativeTo: .body
            )
            .accessibilityHidden(true)

            Text(name)
                .textStyle(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(reaction.kind.emoji)
                .textStyle(.heading)
                .accessibilityHidden(true)
        }
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name), \(reaction.kind.title)")
        .task(id: reaction.id) {
            author = await UserProfileCache.shared.profile(uid: reaction.id)
        }
    }
}
