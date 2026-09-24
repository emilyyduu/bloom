import SwiftUI
import SwiftData

/// The signed-in app's tab bar. Media logging (Movies & TV) and local
/// notifications aren't built yet at this stage, they're Week 9 work, so
/// this is deliberately three content tabs plus Circle.
struct ContentView: View {
    var body: some View {
        TabView {
            DaisyChainView()
                .tabItem {
                    Label("Daisy Chain", systemImage: "list.bullet.rectangle")
                }

            FlipbookView()
                .tabItem {
                    Label("Flipbook", systemImage: "book.pages")
                }

            JournalHistoryListView()
                .tabItem {
                    Label("History", systemImage: "calendar")
                }

            MyCircleView()
                .tabItem {
                    Label("Circle", systemImage: "person.2")
                }
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(PreviewContainer.shared)
}
