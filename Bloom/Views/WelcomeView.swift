import SwiftUI

// The entry point before sign-up or log-in. Shown whenever
// AuthService.isSignedIn is false.
struct WelcomeView: View {
    @State private var isShowingSignUp = false
    @State private var isShowingLogIn = false
    @State private var isShowingAbout = false

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Text("Bloom")
                    .font(.system(.largeTitle, design: .serif))
                    .fontWeight(.bold)
                Text("A shared garden of memories")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 24)

                Button("Sign Up") { isShowingSignUp = true }
                    .buttonStyle(.borderedProminent)
                    .frame(maxWidth: .infinity)

                Button("Log In") { isShowingLogIn = true }
                    .buttonStyle(.bordered)
                    .frame(maxWidth: .infinity)

                Button("About Bloom") { isShowingAbout = true }
                    .font(.footnote)
                    .frame(minHeight: 44)
            }
            .padding(32)
            .frame(maxWidth: 500)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $isShowingSignUp) { SignUpView() }
        .sheet(isPresented: $isShowingLogIn) { LogInView() }
        .sheet(isPresented: $isShowingAbout) {
            NavigationStack {
                AboutView()
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isShowingAbout = false }
                        }
                    }
            }
        }
    }
}

#Preview {
    WelcomeView()
}
