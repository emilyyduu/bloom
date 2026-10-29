import SwiftUI

// Everything Bloom is built on, as a grouped list. Each row is a Link that
// opens the official page in Safari. The data is in AppInfo.
struct AcknowledgementsView: View {
    var body: some View {
        List {
            group("Libraries", systemImage: "shippingbox", items: [AppInfo.firebaseSDK])
            group("Packages used by Firebase", systemImage: "shippingbox.and.arrow.backward", items: AppInfo.firebasePackages)
            group("Services and data", systemImage: "cloud", items: AppInfo.services)
            group("Apple frameworks and assets", systemImage: "apple.logo", items: AppInfo.appleFrameworks)
            group("Design and tools", systemImage: "pencil.and.ruler", items: AppInfo.designTools)
            group("Learning sources", systemImage: "graduationcap", items: AppInfo.learningSources)

            Section {
                Text(AppInfo.generativeAINote)
            } header: {
                AboutSectionHeader("Generative AI", systemImage: "sparkles")
            }

            Section {
                NavigationLink {
                    LicenseDetailView()
                } label: {
                    Text("Open source licenses")
                }
                .accessibilityHint("Shows the full Firebase iOS SDK license")
            } header: {
                AboutSectionHeader("Licenses", systemImage: "doc.text")
            } footer: {
                Text(AppInfo.thankYou)
                    .frame(maxWidth: .infinity)
                    .multilineTextAlignment(.center)
                    .padding(.top, 12)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Acknowledgements")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func group(_ title: String, systemImage: String, items: [AppInfo.Acknowledgement]) -> some View {
        Section {
            ForEach(items) { item in
                AcknowledgementRow(item: item)
            }
        } header: {
            AboutSectionHeader(title, systemImage: systemImage)
        }
    }
}

private struct AcknowledgementRow: View {
    let item: AppInfo.Acknowledgement

    var body: some View {
        Link(destination: item.url) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.name)
                        .font(.body)
                        .foregroundStyle(.primary)
                    Text(item.detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    if let meta {
                        Text(meta)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "arrow.up.right.square")
                    .accessibilityHidden(true)
            }
            .frame(minHeight: 44)
        }
        .accessibilityLabel("Open \(item.name) website")
        .accessibilityHint("Opens in Safari")
    }

    // "Version 12.19.2, Apache License 2.0", whichever parts are known.
    private var meta: String? {
        let parts = [item.version.map { "Version \($0)" }, item.license].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }
}

// The full Firebase iOS SDK license, bundled as a string so it works offline.
struct LicenseDetailView: View {
    var body: some View {
        ScrollView {
            Text(FirebaseLicenseText.text)
                .font(.footnote.monospaced())
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle("Firebase iOS SDK License")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { AcknowledgementsView() }
}
