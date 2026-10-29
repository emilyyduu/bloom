import SwiftUI

// One row of icon buttons for the things a note can have: a camera
// photo, a library photo, a voice memo and a movie or show. Icon only,
// each at least 44 by 44 points. A tool that already has something
// attached shows its filled symbol and a checkmark badge, so the state
// never relies on colour, and its hint says what tapping does.
//
// The row sits above a divider on a bar background, meant to be pinned
// with safeAreaInset(edge: .bottom) so it rides above the keyboard. A
// screen can add its own controls at the right end (the composer puts
// Drafts and Save as Draft there). They share the row when there is
// room, otherwise they drop to a second row, and at accessibility
// text sizes the rows are always stacked.
struct NoteToolsBar<Trailing: View>: View {
    let hasPhoto: Bool
    let hasVoiceMemo: Bool
    let hasMedia: Bool
    let onTakePhoto: () -> Void
    let onChoosePhoto: () -> Void
    let onVoiceMemo: () -> Void
    let onMedia: () -> Void
    @ViewBuilder let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            rows
                .padding(.horizontal)
                .padding(.vertical, 4)
        }
        .background(.bar)
    }

    @ViewBuilder
    private var rows: some View {
        if dynamicTypeSize.isAccessibilitySize {
            stackedRows
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 8) {
                    tools
                    Spacer(minLength: 8)
                    trailing()
                }
                stackedRows
            }
        }
    }

    private var stackedRows: some View {
        VStack(alignment: .leading, spacing: 0) {
            tools
            trailing()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Even spacing, left aligned.
    private var tools: some View {
        HStack(spacing: 8) {
            NoteToolButton(
                title: "Take photo",
                hint: hasPhoto ? "Replace photo with a new picture" : "Opens the camera",
                symbol: "camera",
                attachedSymbol: "camera.fill",
                isAttached: hasPhoto,
                action: onTakePhoto
            )
            NoteToolButton(
                title: "Choose photo",
                hint: hasPhoto ? "Replace photo" : "Pick a photo from your library",
                symbol: "photo.on.rectangle",
                attachedSymbol: "photo.fill.on.rectangle.fill",
                isAttached: hasPhoto,
                action: onChoosePhoto
            )
            NoteToolButton(
                title: "Voice memo",
                hint: hasVoiceMemo
                    ? "Record a new voice memo"
                    : "Record a voice memo of up to \(VoiceMemoRecorder.limitSeconds) seconds",
                symbol: "mic",
                attachedSymbol: "mic.fill",
                isAttached: hasVoiceMemo,
                action: onVoiceMemo
            )
            NoteToolButton(
                title: "Movie or show",
                hint: hasMedia ? "Change movie or show" : "Search for a movie or show to add",
                symbol: "film",
                attachedSymbol: "film.fill",
                isAttached: hasMedia,
                action: onMedia
            )
        }
    }
}

extension NoteToolsBar where Trailing == EmptyView {
    init(
        hasPhoto: Bool,
        hasVoiceMemo: Bool,
        hasMedia: Bool,
        onTakePhoto: @escaping () -> Void,
        onChoosePhoto: @escaping () -> Void,
        onVoiceMemo: @escaping () -> Void,
        onMedia: @escaping () -> Void
    ) {
        self.init(
            hasPhoto: hasPhoto,
            hasVoiceMemo: hasVoiceMemo,
            hasMedia: hasMedia,
            onTakePhoto: onTakePhoto,
            onChoosePhoto: onChoosePhoto,
            onVoiceMemo: onVoiceMemo,
            onMedia: onMedia,
            trailing: { EmptyView() }
        )
    }
}

private struct NoteToolButton: View {
    let title: String
    let hint: String
    let symbol: String
    let attachedSymbol: String
    let isAttached: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isAttached ? attachedSymbol : symbol)
                .font(.title3)
                .overlay(alignment: .bottomTrailing) {
                    if isAttached {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.caption2)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color(.systemBackground), Color.accentColor)
                            .offset(x: 6, y: 4)
                    }
                }
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .accessibilityLabel(title)
        .accessibilityValue(isAttached ? "Added" : "")
        .accessibilityHint(hint)
    }
}

#Preview {
    NoteToolsBar(
        hasPhoto: true,
        hasVoiceMemo: false,
        hasMedia: true,
        onTakePhoto: {},
        onChoosePhoto: {},
        onVoiceMemo: {},
        onMedia: {}
    ) {
        HStack {
            Image(systemName: "doc.text").frame(minWidth: 44, minHeight: 44)
            Button("Save as Draft") {}.frame(minHeight: 44)
        }
    }
}
