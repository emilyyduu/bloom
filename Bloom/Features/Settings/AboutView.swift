import SwiftUI
import UIKit

// The About page: what Bloom is, who made it, what it is built on. Shown
// pushed from Settings > About and in a sheet from the Welcome screen, so it
// has no navigation stack of its own. All of its text comes from AppInfo.
struct AboutView: View {
    var body: some View {
        List {
            headerSection
            aboutSection
            developerSection
            legalSection
            acknowledgementsSection
            footerSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("about.list")
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    // Not a button, just the app's identity.
    private var headerSection: some View {
        Section {
            VStack(spacing: Theme.Spacing.sm) {
                BrandMark()
                Text(AppInfo.appName)
                    .textStyle(.display)
                    .accessibilityAddTraits(.isHeader)
                Text(AppInfo.tagline)
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                Text(AppInfo.versionLine)
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.sm)
            .accessibilityElement(children: .combine)
            .listRowBackground(Theme.Palette.greenTint)
        }
    }

    private var aboutSection: some View {
        Section {
            Text(AppInfo.aboutText)

            VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                Text("What you can do")
                    .textStyle(.subheading)
                    .accessibilityAddTraits(.isHeader)
                ForEach(AppInfo.features) { feature in
                    FeatureRow(feature: feature)
                }
            }
        } header: {
            AboutSectionHeader("About Bloom", systemImage: "info.circle")
        }
    }

    private var developerSection: some View {
        Section {
            DeveloperRow(label: "Name", value: AppInfo.developerName, identifier: "about.name")
            DeveloperRow(label: "Student ID", value: AppInfo.studentID, identifier: "about.studentID")
            DeveloperRow(label: "Unit", value: AppInfo.unit, identifier: "about.unit")
            DeveloperRow(label: "University", value: AppInfo.university, identifier: "about.university")
        } header: {
            AboutSectionHeader("Developer", systemImage: "person.crop.square")
        }
    }

    // Terms, privacy policy and a way to reach the developer, for anyone who
    // wants to report a problem or ask about their data.
    private var legalSection: some View {
        Section {
            if let url = LegalLinks.termsURL {
                legalLink("Terms of Use", systemImage: "doc.text", destination: url)
            }
            if let url = LegalLinks.privacyPolicyURL {
                legalLink("Privacy Policy", systemImage: "hand.raised", destination: url)
            }
            if let url = LegalLinks.supportURL {
                legalLink("Contact the developer", systemImage: "envelope", destination: url)
            }
        } header: {
            AboutSectionHeader("Legal and support", systemImage: "checkmark.shield")
        } footer: {
            Text("To report a note, a comment or a person, use the menu on it in the app.")
        }
    }

    private func legalLink(_ title: String, systemImage: String, destination: URL) -> some View {
        Link(destination: destination) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(Theme.Colors.textPrimary)
                Spacer()
                Image(systemName: "arrow.up.right.square")
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .accessibilityHint("Opens outside Bloom")
    }

    private var acknowledgementsSection: some View {
        Section {
            NavigationLink {
                AcknowledgementsView()
            } label: {
                Text("Acknowledgements")
            }
            .accessibilityHint("Shows the libraries, services and sources Bloom uses")
        } header: {
            AboutSectionHeader("Acknowledgements", systemImage: "heart.text.square")
        }
    }

    private var footerSection: some View {
        Section {
            VStack(spacing: Theme.Spacing.sm) {
                // TMDB asks for its logo next to the attribution. It is only
                // shown when the asset exists, see TMDBLogo in the catalog.
                if UIImage(named: "TMDBLogo") != nil {
                    Image("TMDBLogo")
                        .resizable()
                        .scaledToFit()
                        .frame(height: 24)
                        .accessibilityLabel("TMDB logo")
                }
                Text(AppInfo.tmdbAttribution)
                    .accessibilityIdentifier("about.tmdb")
                Text(AppInfo.footerCredit)
            }
            .textStyle(.caption)
            .foregroundStyle(Theme.Colors.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .listRowBackground(Color.clear)
        }
    }
}

// A section title with its SF Symbol, read as a heading.
struct AboutSectionHeader: View {
    let title: String
    let systemImage: String

    init(_ title: String, systemImage: String) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .textStyle(.callout)
            .fontWeight(.semibold)
            .foregroundStyle(Theme.Colors.textSecondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct FeatureRow: View {
    let feature: AppInfo.Feature

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Theme.Spacing.md) {
            Image(systemName: feature.systemImage)
                .foregroundStyle(Theme.Colors.blooming)
                .frame(width: iconWidth)
                .accessibilityHidden(true)
            Text(feature.title)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// A label and a value. Side by side normally, stacked at accessibility text
// sizes so long values wrap. The value can be selected and copied, and
// VoiceOver reads the row as "Name, Emily Du".
private struct DeveloperRow: View {
    let label: String
    let value: String
    let identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.xs))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Theme.Spacing.md))

        layout {
            Text(label)
                .foregroundStyle(Theme.Colors.textSecondary)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: Theme.Spacing.sm)
            }
            Text(value)
                .textSelection(.enabled)
                .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label), \(value)")
        .accessibilityIdentifier(identifier)
    }
}

#Preview("Light") {
    NavigationStack { AboutView() }
        .preferredColorScheme(.light)
}

#Preview("Dark Accessibility 5") {
    NavigationStack { AboutView() }
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
