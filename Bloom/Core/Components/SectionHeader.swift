import SwiftUI

// The label above a Form or List section (Appearance, Notifications,
// Username, and so on). The system's default Section(String) header
// reads at nearly the same size and weight as the row text beneath it
// once Dynamic Type grows, which breaks the hierarchy between screen
// title, row text and section header. This keeps the header clearly
// secondary at every size, since it's still a scaling text style
// (.callout) rather than a fixed point size.
struct SectionHeader: View {
    let title: String

    init(_ title: String) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .textStyle(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.textSecondary)
    }
}

#Preview {
    Form {
        Section {
            Text("Row text")
        } header: {
            SectionHeader("Appearance")
        }
    }
}
