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
    @State private var isShowingDrafts = false

    @StateObject private var friendService = FriendService.shared
    @StateObject private var draftSaveBanner = DraftSaveBanner.shared
    @StateObject private var linkCoordinator = ProfileLinkCoordinator.shared
    @StateObject private var router = ActivityRouter.shared
    @StateObject private var activity = ActivityStore.shared
    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase
    // Per account, see AccountDefaults.
    @AppStorage private var hasBackfilledPhotoSync: Bool

    init() {
        _hasBackfilledPhotoSync = AppStorage(
            wrappedValue: false, AccountDefaults.key(AccountDefaults.photoBackfillBase)
        )
    }

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
                        .accessibilityLabel("Add note")
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
        .sheet(isPresented: $isShowingDrafts) {
            DraftsView()
        }
        // On its own view rather than a third sheet on the TabView, so
        // the two isPresented sheets above and this item sheet don't
        // share one presentation slot.
        .background {
            Color.clear
                .sheet(item: $linkCoordinator.incoming) { link in
                    AddByLinkSheet(uid: link.uid)
                }
        }
        // Where a tapped notification goes. Its own background view, so it
        // has its own presentation slot like the link sheet above.
        .background {
            Color.clear
                .sheet(item: $router.destination) { destination in
                    if case .feed = destination {
                        NotificationsView()
                    } else {
                        ActivityDestinationSheet(destination: destination)
                    }
                }
        }
        // Reserves space above the tab bar for the "Saved to Drafts"
        // banner rather than overlaying it, so the tab bar is never
        // covered and its taps are never blocked.
        .safeAreaInset(edge: .bottom) {
            if draftSaveBanner.isShowing {
                DraftSavedBanner {
                    draftSaveBanner.dismiss()
                    isShowingDrafts = true
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: draftSaveBanner.isShowing)
        // The app icon badge follows requests waiting plus unread activity.
        .onChange(of: friendService.pendingIncoming.count + activity.unreadCount) { _, count in
            NotificationBadge.shared.update(unread: count)
        }
        .task {
            // A tapped system notification may be waiting for this screen.
            router.markReady()
            friendService.startListening()
            ActivityStore.shared.startListening()
            await NotificationScheduler.shared.refreshReminders(context: context)
            await StreakSyncService.shared.sync(context: context)
            await restoreAndSyncNotes()
        }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task {
                await NotificationScheduler.shared.refreshReminders(context: context)
                await StreakSyncService.shared.sync(context: context)
                await restoreAndSyncNotes()
            }
        }
    }

    // Restore first so reinstalled notes exist, then the one-time photo
    // backfill (which skips notes restore just gave a photo backup),
    // then upload whatever is still pending.
    private func restoreAndSyncNotes() async {
        await NoteSyncService.shared.restore(context: context)
        if !hasBackfilledPhotoSync {
            NoteSyncService.shared.queuePhotosForBackfill(context: context)
            hasBackfilledPhotoSync = true
        }
        // Only posted notes can be pinned, so clear any pin a draft
        // somehow has before the pending notes upload.
        Note.unpinDrafts(in: context)
        await NoteSyncService.shared.syncPending(context: context)
    }
}

// The transient confirmation shown after "Save as Draft". A View
// button opens Drafts directly.
private struct DraftSavedBanner: View {
    let onView: () -> Void

    var body: some View {
        HStack {
            Text("Saved to Drafts")
                .font(.subheadline)
            Spacer()
            Button("View", action: onView)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.15), radius: 6, y: 2)
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.shared)
}
