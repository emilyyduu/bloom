import SwiftUI

// The entry point before sign-up or log-in. Shown whenever
// AuthService.isSignedIn is false.
struct WelcomeView: View {
    @State private var isShowingSignUp = false
    @State private var isShowingLogIn = false
    @State private var isShowingAbout = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var plantsVisible = false

    @ScaledMetric(relativeTo: .largeTitle) private var badgeSize: CGFloat = 96
    @ScaledMetric(relativeTo: .largeTitle) private var badgeIconSize: CGFloat = 44

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: Theme.Spacing.xl)
                    brand
                    Spacer(minLength: Theme.Spacing.xl)
                    plantRow
                    Spacer(minLength: Theme.Spacing.xxl)
                    actions
                }
                .padding(.horizontal, Theme.Spacing.xxl)
                .padding(.vertical, Theme.Spacing.xl)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                // Fills the screen when there is room so the buttons sit at
                // the bottom, and grows past it (scrolling) when there isn't:
                // landscape or the largest text sizes.
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(Theme.Colors.background.ignoresSafeArea())
        .onAppear {
            if reduceMotion {
                plantsVisible = true
            } else {
                withAnimation(.easeOut(duration: 0.8).delay(0.2)) { plantsVisible = true }
            }
        }
        .sheet(isPresented: $isShowingSignUp) { SignUpView() }
        .sheet(isPresented: $isShowingLogIn) { LogInView() }
        .sheet(isPresented: $isShowingAbout) {
            NavigationStack {
                AboutView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingAbout = false }
                                .accessibilityIdentifier("about.close")
                        }
                    }
            }
        }
    }

    // MARK: Sections

    private var brand: some View {
        VStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle().fill(Theme.Colors.actionFill)
                Image(systemName: "leaf.fill")
                    .font(.system(size: badgeIconSize))
                    .foregroundStyle(Theme.Colors.onActionFill)
            }
            .frame(width: badgeSize, height: badgeSize)
            .accessibilityHidden(true)

            Text("Bloom")
                .textStyle(.display)
                .accessibilityAddTraits(.isHeader)
            Text("A shared garden of memories")
                .textStyle(.subheading)
                .foregroundStyle(Theme.Colors.textSecondary)
            Text("Write small notes through the day and watch your garden grow.")
                .textStyle(.callout)
                .foregroundStyle(Theme.Colors.textSecondary)
                .padding(.top, Theme.Spacing.xs)
        }
        .multilineTextAlignment(.center)
    }

    // Seedling, leaf, flower. Purely decorative, so VoiceOver skips it,
    // and with Reduce Motion on it is simply shown without fading in.
    private var plantRow: some View {
        HStack(alignment: .bottom, spacing: Theme.Spacing.xxl) {
            plant("sprout.fill", size: .heading)
            plant("leaf.fill", size: .title)
            plant("camera.macro", size: .display)
        }
        .opacity(plantsVisible ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func plant(_ name: String, size: Theme.TextStyle) -> some View {
        Image(systemName: name)
            .textStyle(size)
            .foregroundStyle(Theme.Colors.actionFill)
    }

    private var actions: some View {
        VStack(spacing: Theme.Spacing.md) {
            Button { isShowingSignUp = true } label: {
                Text("Sign Up")
            }
            .buttonStyle(.bloomPrimary)
            .accessibilityIdentifier("welcome.signUp")

            Button { isShowingLogIn = true } label: {
                Text("Log In")
            }
            .buttonStyle(.bloomSecondary)
            .accessibilityIdentifier("welcome.logIn")

            Button("About Bloom") { isShowingAbout = true }
                .textStyle(.caption)
                .foregroundStyle(Theme.Colors.greenText)
                .frame(minHeight: 44)
                .accessibilityIdentifier("welcome.about")
        }
    }
}

#Preview("Light") {
    WelcomeView()
}

#Preview("Dark") {
    WelcomeView()
        .preferredColorScheme(.dark)
}

#Preview("Dark Accessibility 5") {
    WelcomeView()
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
