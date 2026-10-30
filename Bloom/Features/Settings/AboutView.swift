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
            acknowledgementsSection
            footerSection
        }
        .listStyle(.insetGrouped)
        .accessibilityIdentifier("about.list")
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: Sections

    // Not a button, just the app's identity.
    private var headerSection: some View {
        Section {
            VStack(spacing: 8) {
                Image(systemName: "leaf.fill")
                    .font(.largeTitle)
                    .foregroundStyle(Theme.Colors.blooming)
                    .accessibilityHidden(true)
                Text(AppInfo.appName)
                    .font(.system(.largeTitle, design: .serif))
                    .fontWeight(.bold)
                    .accessibilityAddTraits(.isHeader)
                Text(AppInfo.tagline)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(AppInfo.versionLine)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .accessibilityElement(children: .combine)
            .listRowBackground(Theme.Colors.gardenCardBackground)
        }
    }

    private var aboutSection: some View {
        Section {
            Text(AppInfo.aboutText)

            VStack(alignment: .leading, spacing: 12) {
                Text("What you can do")
                    .font(.headline)
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
            VStack(spacing: 8) {
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
            .font(.footnote)
            .foregroundStyle(.secondary)
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
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(.secondary)
            .textCase(nil)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct FeatureRow: View {
    let feature: AppInfo.Feature

    @ScaledMetric(relativeTo: .body) private var iconWidth: CGFloat = 24

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
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
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))

        layout {
            Text(label)
                .foregroundStyle(.secondary)
            if !dynamicTypeSize.isAccessibilitySize {
                Spacer(minLength: 8)
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
