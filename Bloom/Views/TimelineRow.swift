import SwiftUI

// The chain every timeline in Bloom uses: the time on the left with a dot
// and a connecting line under it, and a card to the right. Home's Today
// timeline and the journal Day screens both use this one view, so they
// always match. At accessibility text sizes the time moves above the card,
// since the left column can't stay narrow.
struct TimelineRow<Card: View>: View {
    let date: Date
    let isLast: Bool
    @ViewBuilder let card: () -> Card

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var timeColumnWidth: CGFloat = 44

    private var time: TimeDisplay { timeDisplay(for: date) }

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
        .accessibilityHidden(true)
    }

    var body: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                timeLabel
                card()
            }
            .padding(.bottom, 16)
        } else {
            HStack(alignment: .top, spacing: 12) {
                VStack(spacing: 6) {
                    timeLabel
                    TimelineConnector(isLast: isLast)
                }
                .frame(width: timeColumnWidth)

                card()
            }
            .padding(.bottom, 16)
        }
    }
}

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
        .accessibilityHidden(true)
    }
}

// The card chrome: a filled, bordered rounded rectangle that opens the
// note when tapped.
private struct TimelineCardStyle: ViewModifier {
    let onTap: () -> Void

    func body(content: Content) -> some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 24).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color(.separator), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 24))
            .onTapGesture(perform: onTap)
    }
}

extension View {
    func timelineCardStyle(onTap: @escaping () -> Void) -> some View {
        modifier(TimelineCardStyle(onTap: onTap))
    }
}

// My own note on the chain.
struct NoteTimelineCard: View {
    let note: Note
    let onComment: () -> Void
    let onTap: () -> Void

    var body: some View {
        // A note deleted a moment ago, before the list catches up.
        if note.isDeleted || note.modelContext == nil {
            EmptyView()
        } else {
            card
        }
    }

    private var card: some View {
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
        .timelineCardStyle(onTap: onTap)
        .noteActions(note)
    }
}

// A friend's shared note on the chain, read only.
struct FriendTimelineCard: View {
    let friend: FirestoreUser
    let note: FriendNote
    let onComment: () -> Void
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !note.text.isEmpty {
                Text(note.text)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            if let friendUID = friend.id {
                FriendVoiceMemo(friendUID: friendUID, note: note)

                // Only the notes that report a photo are fetched, and only
                // when the card scrolls on screen.
                if note.hasPhoto, let noteID = note.id {
                    FriendNotePhoto(friendUID: friendUID, noteID: noteID)
                }
            }

            HStack {
                Spacer()
                CommentBubbleButton(ownerUID: friend.id, noteID: note.id, action: onComment)
            }
        }
        .timelineCardStyle(onTap: onTap)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            "\(friend.shownName), \(note.createdAt.formatted(date: .omitted, time: .shortened)), \(note.text)"
                + (note.hasPhoto ? ", has a photo" : "")
                + (note.hasAudio == true ? ", has a voice memo" : "")
        )
        .accessibilityAddTraits(.isButton)
    }
}

// MARK: - Time

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
