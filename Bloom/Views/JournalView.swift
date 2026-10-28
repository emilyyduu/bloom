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
            .sheet(isPresented: $isShowingMediaSearch) {
                MediaSearchView()
            }
            .sheet(isPresented: $isShowingDrafts) {
                DraftsView()
            }
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
