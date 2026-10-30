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
                    Spacer(minLength: 24)
                    brand
                    Spacer(minLength: 24)
                    plantRow
                    Spacer(minLength: 32)
                    actions
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 24)
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
                // Fills the screen when there is room so the buttons sit at
                // the bottom, and grows past it (scrolling) when there isn't:
                // landscape or the largest text sizes.
                .frame(minHeight: proxy.size.height)
            }
        }
        .background(
            LinearGradient(
                colors: [Color(.systemBackground), Theme.Colors.welcomeGradientBottom],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
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
        VStack(spacing: 12) {
            ZStack {
                Circle().fill(Theme.Colors.actionFill)
                Image(systemName: "leaf.fill")
                    .font(.system(size: badgeIconSize))
                    .foregroundStyle(Theme.Colors.onActionFill)
            }
            .frame(width: badgeSize, height: badgeSize)
            .accessibilityHidden(true)

            Text("Bloom")
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
                .accessibilityAddTraits(.isHeader)
            Text("A shared garden of memories")
                .font(.headline)
                .foregroundStyle(Theme.Colors.welcomeSecondaryText)
            Text("Write small notes through the day and watch your garden grow.")
                .font(.subheadline)
                .foregroundStyle(Theme.Colors.welcomeSecondaryText)
                .padding(.top, 4)
        }
        .multilineTextAlignment(.center)
    }

    // Seedling, leaf, flower. Purely decorative, so VoiceOver skips it,
    // and with Reduce Motion on it is simply shown without fading in.
    private var plantRow: some View {
        HStack(alignment: .bottom, spacing: 28) {
            plant("sprout.fill", size: .title2)
            plant("leaf.fill", size: .title)
            plant("camera.macro", size: .largeTitle)
        }
        .opacity(plantsVisible ? 1 : 0)
        .accessibilityHidden(true)
    }

    private func plant(_ name: String, size: Font.TextStyle) -> some View {
        Image(systemName: name)
            .font(.system(size, design: .default))
            .foregroundStyle(Theme.Colors.actionFill)
    }

    private var actions: some View {
        VStack(spacing: 12) {
            Button { isShowingSignUp = true } label: {
                Text("Sign Up")
            }
            .buttonStyle(WelcomeButtonStyle(isProminent: true))
            .accessibilityIdentifier("welcome.signUp")

            Button { isShowingLogIn = true } label: {
                Text("Log In")
            }
            .buttonStyle(WelcomeButtonStyle(isProminent: false))
            .accessibilityIdentifier("welcome.logIn")

            Button("About Bloom") { isShowingAbout = true }
                .font(.footnote)
                .foregroundStyle(Theme.Colors.actionFill)
                .frame(minHeight: 44)
                .accessibilityIdentifier("welcome.about")
        }
    }
}

// Full width rounded button, at least 50 points tall. Primary is filled,
// secondary is bordered. Both colours come from Theme and were checked in
// light and dark mode.
private struct WelcomeButtonStyle: ButtonStyle {
    let isProminent: Bool

    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        configuration.label
            .font(.headline)
            .foregroundStyle(isProminent ? Theme.Colors.onActionFill : Theme.Colors.actionFill)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50)
            .background {
                if isProminent {
                    shape.fill(Theme.Colors.actionFill)
                }
            }
            .overlay {
                if !isProminent {
                    shape.strokeBorder(Theme.Colors.actionFill, lineWidth: 1.5)
                }
            }
            .contentShape(shape)
            .opacity(configuration.isPressed ? 0.7 : (isEnabled ? 1 : 0.5))
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
