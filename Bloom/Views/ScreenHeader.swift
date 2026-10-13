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

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .top) {
            Text(title)
                .font(.largeTitle.bold())
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Spacer(minLength: 8)

            trailing()
        }
        .padding(.horizontal)
        .padding(.top, 10)
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
