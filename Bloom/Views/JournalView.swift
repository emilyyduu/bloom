import SwiftUI
import SwiftData

// The Journal tab: the same day's notes shown three ways, switched
// with a segmented control rather than three separate tabs.
struct JournalView: View {
    private enum Segment: String, CaseIterable {
        case daisyChain = "Daisy Chain"
        case flipbook = "Flipbook"
        case library = "Library"
    }

    @State private var segment: Segment = .daisyChain
    @State private var isShowingMediaSearch = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Journal View", selection: $segment) {
                    ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)

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
            }
            .navigationTitle(segment.rawValue)
            .toolbar {
                if segment == .library {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            isShowingMediaSearch = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }
                        .accessibilityLabel("Log a movie or show")
                    }
                }
            }
            .sheet(isPresented: $isShowingMediaSearch) {
                MediaSearchView()
            }
        }
    }
}

#Preview {
    JournalView()
        .modelContainer(PreviewContainer.shared)
}
