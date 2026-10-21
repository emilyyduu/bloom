import SwiftUI
import SwiftData

// The page-by-page view: today's notes shown one at a time, swiped
// through horizontally like a small book.
struct FlipbookView: View {
    @Query(Note.todaysNotesDescriptor()) private var todaysNotes: [Note]
    @State private var noteToShare: Note?

    var body: some View {
        Group {
            if todaysNotes.isEmpty {
                ContentUnavailableView(
                    "No pages yet",
                    systemImage: "book",
                    description: Text("Notes you add today will appear here as pages.")
                )
            } else {
                TabView {
                    ForEach(todaysNotes) { note in
                        FlipbookPage(note: note, onShare: { noteToShare = note })
                            .padding(.horizontal, 16)
                            .padding(.top, 16)
                            .padding(.bottom, 36)
                    }
                }
                .tabViewStyle(.page)
                .indexViewStyle(.page(backgroundDisplayMode: .always))
            }
        }
        .sheet(item: $noteToShare) { note in
            ShareNoteSheet(note: note)
        }
    }
}

private struct FlipbookPage: View {
    let note: Note
    let onShare: () -> Void

    @Environment(\.verticalSizeClass) private var verticalSizeClass

    // In landscape on iPhone (compact height) the photo and text sit
    // side by side instead of stacked, so neither gets squeezed into a
    // sliver of the limited height.
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var contentLayout: AnyLayout {
        isCompactHeight
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            : AnyLayout(VStackLayout(spacing: 16))
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 8) {
                    Text(note.createdAt, style: .time)
                        .font(.headline)
                        .foregroundStyle(.secondary)
                    if note.sharedWithFriends {
                        SharedIndicator()
                    }
                    Spacer()
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                    }
                    .accessibilityLabel("Share note")
                }

                contentLayout {
                    if let photo = note.photo {
                        Image(uiImage: photo)
                            .resizable()
                            .scaledToFit()
                            .frame(maxWidth: isCompactHeight ? nil : .infinity)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                    }

                    VStack(spacing: 12) {
                        Text(note.text)
                            .font(.title3)
                            .multilineTextAlignment(.center)

                        if let mediaLogEntry = note.mediaLogEntry {
                            MediaLogChip(entry: mediaLogEntry)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity)
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    NavigationStack {
        FlipbookView()
    }
    .modelContainer(PreviewContainer.shared)
}
