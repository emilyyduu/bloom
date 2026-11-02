import SwiftUI

// The large, left aligned title used at the top of each tab's root
// screen (Home, Journal, Greenhouse, Profile), in place of a standard
// navigation bar title.
//
// A standard .navigationBarTitleDisplayMode(.large) title sits roughly
// 100pt down the screen: the navigation bar still reserves its usual
// compact bar row (for a back button or trailing items) directly under
// the status bar, and the large title renders as a second, separate
// row below that empty bar. ScreenHeader replaces both of those with a
// single title pinned just under the safe area, on root screens where
// .toolbar(.hidden, for: .navigationBar) removes the standard bar
// entirely.
struct ScreenHeader<Trailing: View>: View {
    let title: String
    private let trailing: () -> Trailing

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    // At accessibility sizes the title can easily run to two or three
    // lines, so the trailing button moves below it instead of being
    // squeezed into a shrinking sliver beside it.
    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Theme.Spacing.sm))
    }

    var body: some View {
        layout {
            Text(title)
                .textStyle(isCompactHeight ? .heading : .title)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if dynamicTypeSize.isAccessibilitySize {
                trailing()
            } else {
                Spacer(minLength: Theme.Spacing.sm)
                trailing()
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.top, isCompactHeight ? Theme.Spacing.sm : 10)
        .padding(.bottom, isCompactHeight ? Theme.Spacing.sm : 0)
        // Intentionally transparent: this component doesn't know what
        // kind of content sits below it (a List's grouped grey, a plain
        // ScrollView's system background, and so on), so it never paints
        // its own background. Each screen is responsible for giving its
        // outer container a background that matches its content, so
        // there's no seam between the header and whatever follows it.
        .background(Color.clear)
    }
}

#Preview {
    VStack {
        ScreenHeader("Greenhouse")
        ScreenHeader("Library") {
            Button {
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .accessibilityLabel("Log a movie or show")
        }
        Spacer()
    }
}
