import SwiftUI

/// The entry point before sign-up or log-in. Shown whenever
/// AuthService.isSignedIn is false.
struct WelcomeView: View {
    @State private var isShowingSignUp = false
    @State private var isShowingLogIn = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Text("Bloom")
                .font(.system(.largeTitle, design: .serif))
                .fontWeight(.bold)
            Text("A shared garden of memories")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Spacer()

            Button("Sign Up") { isShowingSignUp = true }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)

            Button("Log In") { isShowingLogIn = true }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)
        }
        .padding(32)
        .sheet(isPresented: $isShowingSignUp) { SignUpView() }
        .sheet(isPresented: $isShowingLogIn) { LogInView() }
    }
}

#Preview {
    WelcomeView()
}
