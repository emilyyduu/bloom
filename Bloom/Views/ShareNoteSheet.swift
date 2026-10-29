import SwiftUI

// A small, non-colour-only badge for a note that's currently shared
// with friends. Pairs the SF Symbol with the word "Shared" so the
// state doesn't rely on colour alone.
struct SharedIndicator: View {
    var body: some View {
        Label("Shared", systemImage: "person.2.fill")
            .font(.caption2)
            .fontWeight(.medium)
            .foregroundStyle(.secondary)
    }
}
