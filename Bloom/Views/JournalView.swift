import SwiftUI
import SwiftData

// The Journal tab: the same day's notes shown two ways, switched with
// a segmented control rather than two separate tabs.
struct JournalView: View {
    enum Segment: String, CaseIterable {
        case todaysNotes = "Today's Notes"
        case library = "Library"
    }

    @State private var segment: Segment
    @State private var isShowingMediaSearch = false
    // The Library flow: search, then review, then the attach choice.
    // Each step is handed on when the previous sheet has finished
    // dismissing, so two sheets are never swapped at once.
    @State private var chosenMedia: MediaReviewDraft?
    @State private var attachingMedia: MediaReviewDraft?
    @State private var pendingComposerMedia: MediaReviewDraft?
    @State private var composerMedia: MediaReviewDraft?
    @Environment(\.modelContext) private var context
    @State private var isShowingDrafts = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    @Query(filter: #Predicate<Note> { $0.isDraft }) private var drafts: [Note]

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    init(initialSegment: Segment = .todaysNotes) {
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(segment.rawValue) {
                    HStack(spacing: 12) {
                        if segment == .library {
                            Button {
                                isShowingMediaSearch = true
                            } label: {
                                Image(systemName: "magnifyingglass")
                            }
                            .frame(minWidth: 44, minHeight: 44)
                            .accessibilityLabel("Log a movie or show")
                        }

                        draftsButton
                    }
                }

                // Segment labels truncate at accessibility sizes in a
                // segmented control, so it becomes a menu instead.
                if dynamicTypeSize.isAccessibilitySize {
                    Picker("Journal View", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal)
                    .padding(.top, 8)
                } else {
                    Picker("Journal View", selection: $segment) {
                        ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .padding(.top, 8)
                }

                Group {
                    switch segment {
                    case .todaysNotes:
                        TodaysNotesView()
                    case .library:
                        LibraryView()
                    }
                }
                .frame(maxWidth: isCompactHeight ? 700 : .infinity)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle(segment.rawValue)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingMediaSearch, onDismiss: {
                attachingMedia = chosenMedia
                chosenMedia = nil
            }) {
                MediaSearchView { chosenMedia = $0 }
            }
            .sheet(item: $attachingMedia, onDismiss: {
                composerMedia = pendingComposerMedia
                pendingComposerMedia = nil
            }) { draft in
                MediaAttachChoiceSheet(draft: draft) { choice in
                    handle(choice, for: draft)
                }
            }
            .sheet(item: $composerMedia) { draft in
                NoteComposerView(attaching: draft)
            }
            .sheet(isPresented: $isShowingDrafts) {
                DraftsView()
            }
        }
    }

    private func handle(_ choice: MediaAttachChoice, for draft: MediaReviewDraft) {
        switch choice {
        case .none:
            _ = MediaLogEntry.create(from: draft, note: nil, in: context)
            try? context.save()
        case .note(let note):
            _ = MediaLogEntry.create(from: draft, note: note, in: context)
            try? context.save()
        case .newNote:
            // The entry is created when that note is saved.
            pendingComposerMedia = draft
        }
    }

    // Visible even at zero drafts, so it's always findable; the count
    // badge is an addition, not the only way to tell drafts exist.
    private var draftsButton: some View {
        Button {
            isShowingDrafts = true
        } label: {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "doc.text")
                if !drafts.isEmpty {
                    Text("\(drafts.count)")
                        .font(.caption2)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(4)
                        .background(Circle().fill(Color.red))
                        .offset(x: 10, y: -10)
                }
            }
            .frame(minWidth: 44, minHeight: 44)
        }
        .accessibilityLabel("Drafts")
        .accessibilityValue("\(drafts.count) draft\(drafts.count == 1 ? "" : "s")")
    }
}

#Preview("Light") {
    JournalView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    JournalView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}

#Preview("Today's Notes - Large") {
    JournalView(initialSegment: .todaysNotes)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Today's Notes - XXX Large") {
    JournalView(initialSegment: .todaysNotes)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Today's Notes - Accessibility 5") {
    JournalView(initialSegment: .todaysNotes)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Library - Large") {
    JournalView(initialSegment: .library)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Library - XXX Large") {
    JournalView(initialSegment: .library)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Library - Accessibility 5") {
    JournalView(initialSegment: .library)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .accessibility5)
}
