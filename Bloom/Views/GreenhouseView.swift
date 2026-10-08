import SwiftUI

// Placeholder for the shared circle garden. The SceneKit scene and
// streak tracking are not built yet, so this stays an honest empty
// state rather than fake content.
struct GreenhouseView: View {
    var body: some View {
        NavigationStack {
            ContentUnavailableView(
                "Coming Soon",
                systemImage: "leaf",
                description: Text("Your circle's garden and streaks will show here.")
            )
            .navigationTitle("Greenhouse")
        }
    }
}

#Preview {
    GreenhouseView()
}
