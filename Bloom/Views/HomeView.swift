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

    private var hasRecentItems: Bool {
        !friendService.pendingIncoming.isEmpty || !sharedNotes.isEmpty
    }

    var body: some View {
        NavigationStack {
            List {
                Section("Today") {
                    Label(
                        "\(todaysNotes.count) petal\(todaysNotes.count == 1 ? "" : "s") logged today",
                        systemImage: "leaf"
                    )
                }

                Section("Quick Actions") {
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
                }

                Section("Recent") {
                    if hasRecentItems {
                        ForEach(friendService.pendingIncoming) { request in
                            HStack {
                                Text("\(friendService.pendingRequesterNames[request.fromUID] ?? "Someone") wants to be friends")
                                Spacer()
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
                }
            }
            .navigationTitle("Home")
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
}

#Preview {
    HomeView(selectedTab: .constant(.home))
        .modelContainer(PreviewContainer.shared)
}
