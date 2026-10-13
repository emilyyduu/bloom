import SwiftUI
import SwiftData

// The signed-in app's tab bar: Home, Journal, Add (a sheet trigger, not
// a screen), Greenhouse and Profile.
struct ContentView: View {
    enum Tab: Hashable {
        case home, journal, add, greenhouse, profile
    }

    @State private var selectedTab: Tab = .home
    @State private var tabBeforeAdd: Tab = .home
    @State private var isShowingComposer = false

    @StateObject private var friendService = FriendService.shared
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage("dailyReminderEnabled") private var isDailyReminderEnabled = false

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView(selectedTab: $selectedTab)
                .tabItem {
                    Label("Home", systemImage: "house")
                }
                .tag(Tab.home)

            JournalView()
                .tabItem {
                    Label("Journal", systemImage: "book")
                }
                .tag(Tab.journal)

            Color.clear
                .tabItem {
                    Label("Add", systemImage: "plus.circle.fill")
                        .accessibilityLabel("Add petal")
                }
                .tag(Tab.add)

            GreenhouseView()
                .tabItem {
                    Label("Greenhouse", systemImage: "leaf")
                }
                .tag(Tab.greenhouse)

            ProfileView()
                .tabItem {
                    Label("Profile", systemImage: "person")
                }
                .tag(Tab.profile)
                .badge(friendService.pendingIncoming.count)
        }
        // The Add tab is never actually shown: selecting it snaps the
        // selection back to whichever tab was visible before and opens
        // the composer as a sheet instead.
        .onChange(of: selectedTab) { _, newValue in
            guard newValue == .add else {
                tabBeforeAdd = newValue
                return
            }
            selectedTab = tabBeforeAdd
            isShowingComposer = true
        }
        .sheet(isPresented: $isShowingComposer) {
            NoteComposerView()
        }
        .task {
            friendService.startListening()
            await NotificationScheduler.shared.refreshReminders(enabled: isDailyReminderEnabled, context: context)
            await StreakSyncService.shared.sync(context: context)
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await NotificationScheduler.shared.refreshReminders(enabled: isDailyReminderEnabled, context: context)
                await StreakSyncService.shared.sync(context: context)
            }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.shared)
}
