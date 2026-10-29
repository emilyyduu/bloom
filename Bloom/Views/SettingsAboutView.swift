import SwiftUI

// Settings > About: the app, its version and where the movie data comes
// from.
struct SettingsAboutView: View {
    private static let tmdbAttribution =
        "This product uses the TMDB API but is not endorsed or certified by TMDB."

    private var appName: String {
        let info = Bundle.main
        return info.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? info.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Bloom"
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("App", value: appName)
                LabeledContent("Version", value: version)
                LabeledContent("Build", value: build)
            }

            Section {
                Text(Self.tmdbAttribution)
                NavigationLink("Acknowledgements") {
                    AcknowledgementsView(tmdbAttribution: Self.tmdbAttribution)
                }
                .frame(minHeight: 44)
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// The services Bloom is built on.
private struct AcknowledgementsView: View {
    let tmdbAttribution: String

    var body: some View {
        Form {
            Section {
                Text(tmdbAttribution)
                Link("themoviedb.org", destination: URL(string: "https://www.themoviedb.org")!)
                    .frame(minHeight: 44, alignment: .leading)
            } header: {
                SectionHeader("TMDB")
            } footer: {
                Text("Movie and show details in the Library come from TMDB.")
            }

            Section {
                Text("Sign in, backup and sharing use Firebase, released under the Apache License 2.0.")
                Link("firebase.google.com", destination: URL(string: "https://firebase.google.com")!)
                    .frame(minHeight: 44, alignment: .leading)
            } header: {
                SectionHeader("Firebase")
            }
        }
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Light") {
    NavigationStack { SettingsAboutView() }
        .preferredColorScheme(.light)
}

#Preview("Dark Accessibility 5") {
    NavigationStack { SettingsAboutView() }
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
