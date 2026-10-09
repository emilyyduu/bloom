import SwiftUI
import SwiftData

// The vertical timeline view: every note logged today, in order, each
// linked to the next like flowers in a chain. A note appears here the
// moment it's saved, there is no publish step.
struct DaisyChainView: View {
    @Environment(\.modelContext) private var context
    @Query(Note.todaysNotesDescriptor()) private var todaysNotes: [Note]

    @State private var noteToShare: Note?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(todaysNotes.enumerated()), id: \.element.id) { index, note in
                    DaisyChainRow(note: note, isLast: index == todaysNotes.count - 1) {
                        noteToShare = note
                    }
                }

                if todaysNotes.isEmpty {
                    ContentUnavailableView(
                        "No notes yet today",
                        systemImage: "leaf",
                        description: Text("Tap Add to add the first petal to today's chain.")
                    )
                    .padding(.top, 60)
                }
            }
            .padding()
        }
        .sheet(item: $noteToShare) { note in
            ShareToFriendView(note: note)
        }
    }
}

private struct DaisyChainRow: View {
    let note: Note
    let isLast: Bool
    let onShare: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 10, height: 10)
                if !isLast {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.3))
                        .frame(width: 2)
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(note.createdAt, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(action: onShare) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.caption)
                    }
                }

                Text(note.text)
                    .font(.body)

                if let photo = note.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(height: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .clipped()
                }

                if let mediaLogEntry = note.mediaLogEntry {
                    MediaLogChip(entry: mediaLogEntry)
                }
            }
            .padding(.bottom, 20)
        }
    }
}

#Preview {
    NavigationStack {
        DaisyChainView()
    }
    .modelContainer(PreviewContainer.shared)
}
