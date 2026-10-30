import SwiftUI
import FirebaseAuth

// The Reactions row of the note detail sheet: the six reactions with
// their counts, my choice ringed, and a link to who reacted. Only shared,
// posted notes have reactions, so the sheet leaves this out otherwise.
struct ReactionsSection: View {
    @ObservedObject var listener: NoteReactionsListener
    // On a Today's Notes card the heading is left out to save height.
    var isCompact = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var isShowingReactors = false

    private var myUID: String? { Auth.auth().currentUser?.uid }
    private var myReaction: ReactionKind? { listener.myReaction(uid: myUID) }

    // Six across normally, two rows of three at large text sizes.
    private var columns: [GridItem] {
        let count = dynamicTypeSize >= .xxxLarge ? 3 : 6
        return Array(repeating: GridItem(.flexible(), spacing: 8), count: count)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: isCompact ? 4 : 12) {
            if !isCompact {
                Text("Reactions")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
            }

            switch listener.state {
            case .loading:
                ProgressView("Loading reactions")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            case .permissionDenied:
                notice("You can\u{2019}t see these reactions", systemImage: "lock")
            case .missingIndex:
                notice("Reactions aren\u{2019}t available yet", systemImage: "exclamationmark.triangle")
            case .failed:
                LiveFailedNotice(text: "Couldn\u{2019}t load reactions", retry: listener.retry)
            case .loaded:
                LazyVGrid(columns: columns, spacing: 8) {
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
                    Button("See who reacted") { isShowingReactors = true }
                        .font(.subheadline)
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
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
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
                    .font(.title3)
                Text("\(count)")
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .monospacedDigit()
                    .foregroundStyle(isSelected ? Color.primary : Color.secondary)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? Color.accentColor.opacity(0.18) : Color(.secondarySystemBackground))
            )
            .overlay {
                if isSelected {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(Color.accentColor, lineWidth: 2)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(kind.title), \(count) \(count == 1 ? "reaction" : "reactions")")
        .accessibilityHint(isSelected ? "Removes your reaction" : "Reacts with \(kind.title.lowercased())")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// Who reacted and with what, newest first. Reads the same live listener
// as the row, so it stays current while open.
private struct ReactorsSheet: View {
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
        HStack(spacing: 12) {
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
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(reaction.kind.emoji)
                .font(.title2)
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
