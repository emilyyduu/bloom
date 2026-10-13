import SwiftUI
import SwiftData

// The Journal tab: the same day's notes shown three ways, switched
// with a segmented control rather than three separate tabs.
struct JournalView: View {
    enum Segment: String, CaseIterable {
        case daisyChain = "Daisy Chain"
        case flipbook = "Flipbook"
        case library = "Library"
    }

    @State private var segment: Segment
    @State private var isShowingMediaSearch = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    init(initialSegment: Segment = .daisyChain) {
        _segment = State(initialValue: initialSegment)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader(segment.rawValue) {
                    if segment == .library {
                        Button {
                            isShowingMediaSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityLabel("Log a movie or show")
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
                    case .daisyChain:
                        DaisyChainView()
                    case .flipbook:
                        FlipbookView()
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
        }
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

#Preview("Daisy Chain - Large") {
    JournalView(initialSegment: .daisyChain)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Daisy Chain - XXX Large") {
    JournalView(initialSegment: .daisyChain)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Daisy Chain - Accessibility 5") {
    JournalView(initialSegment: .daisyChain)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Flipbook - Large") {
    JournalView(initialSegment: .flipbook)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Flipbook - XXX Large") {
    JournalView(initialSegment: .flipbook)
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Flipbook - Accessibility 5") {
    JournalView(initialSegment: .flipbook)
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
