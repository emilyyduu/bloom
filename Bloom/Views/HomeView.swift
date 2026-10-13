import SwiftUI
import SwiftData

// The landing tab: how many petals are logged today, two quick
// actions, and anything in my circle that needs my attention right now.
struct HomeView: View {
    @Binding var selectedTab: ContentView.Tab

    @Query(Note.todaysNotesDescriptor()) private var todaysNotes: [Note]
    @StateObject private var friendService = FriendService.shared
    @State private var sharedNotes: [SharedNote] = []
    @State private var isShowingComposer = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    // At accessibility sizes the Accept button moves below the request
    // text instead of squeezing it into a shrinking leading column.
    private var requestRowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout())
    }

    // In landscape on iPhone (compact height), Today and Quick Actions
    // sit in a left column with Recent in a right column, each its own
    // scrollable list, instead of one on top of the other.
    private var columnsLayout: AnyLayout {
        isCompactHeight
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
    }

    private var hasRecentItems: Bool {
        !friendService.pendingIncoming.isEmpty || !sharedNotes.isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader("Home")

                columnsLayout {
                    todayAndQuickActionsList
                    recentList
                }
            }
            // Matches the List's own grouped background, so the clear
            // area behind the header isn't a different colour than the
            // list beneath it.
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $isShowingComposer) {
                NoteComposerView()
            }
            .task {
                friendService.startListening()
                SharingService.shared.listenForSharedNotes { notes in
                    sharedNotes = notes
                }
            }
        }
    }

    private var todayAndQuickActionsList: some View {
        List {
            Section {
                Label(
                    "\(todaysNotes.count) petal\(todaysNotes.count == 1 ? "" : "s") logged today",
                    systemImage: "leaf"
                )
            } header: {
                SectionHeader("Today")
            }

            Section {
                Button {
                    isShowingComposer = true
                } label: {
                    Label("Add Petal", systemImage: "plus.circle")
                }
                Button {
                    selectedTab = .greenhouse
                } label: {
                    Label("Streaks", systemImage: "flame")
                }
            } header: {
                SectionHeader("Quick Actions")
            }
        }
        .listSectionSpacing(isCompactHeight ? .compact : .default)
        .frame(maxWidth: isCompactHeight ? 350 : .infinity)
    }

    private var recentList: some View {
        List {
            Section {
                if hasRecentItems {
                    ForEach(friendService.pendingIncoming) { request in
                        requestRowLayout {
                            Text("\(friendService.pendingRequesterNames[request.fromUID] ?? "Someone") wants to be friends")
                            if !dynamicTypeSize.isAccessibilitySize {
                                Spacer()
                            }
                            Button("Accept") {
                                Task { try? await friendService.acceptFriendRequest(request) }
                            }
                            .buttonStyle(.borderedProminent)
                        }
                    }

                    ForEach(sharedNotes) { shared in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(shared.text)
                            Text(shared.sharedAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Nothing new right now.")
                        .foregroundStyle(.secondary)
                }
            } header: {
                SectionHeader("Recent")
            }
        }
        .listSectionSpacing(isCompactHeight ? .compact : .default)
        .frame(maxWidth: isCompactHeight ? 700 : .infinity)
    }
}

#Preview("Light") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type - Large") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Dynamic Type - XXX Large") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Dynamic Type - Accessibility 5") {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .accessibility5)
}
