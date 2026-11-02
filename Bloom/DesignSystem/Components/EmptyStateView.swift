import SwiftUI

// The empty state used on list screens: an icon, a heading and a one line
// subheading, with an optional button underneath. Built by hand rather than
// ContentUnavailableView so every screen reads the same as "No notes today".
struct EmptyStateView<Actions: View>: View {
    let title: String
    let message: String
    let systemImage: String
    @ViewBuilder var actions: Actions

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: systemImage)
                    .textStyle(.display)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
                Text(title)
                    .textStyle(.heading)
                Text(message)
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            actions
        }
        .padding(.horizontal, Theme.Spacing.screenEdge)
        .frame(maxWidth: 400)
    }
}

extension EmptyStateView where Actions == EmptyView {
    init(title: String, message: String, systemImage: String) {
        self.init(title: title, message: message, systemImage: systemImage) { EmptyView() }
    }
}

#Preview {
    EmptyStateView(title: "No friends yet", message: "Add someone to start sharing notes.", systemImage: "person.2")
}
