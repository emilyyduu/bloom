import SwiftUI

// Settings > Display: the appearance and a pointer to the iPhone's text
// size. Appearance is applied at the app root in BloomApp and is shared
// by every account on this device. There are no other themes.
struct SettingsDisplayView: View {
    @AppStorage("appearance") private var appearanceRawValue = AppAppearance.system.rawValue

    private var appearance: Binding<AppAppearance> {
        Binding(
            get: { AppAppearance(rawValue: appearanceRawValue) ?? .system },
            set: { appearanceRawValue = $0.rawValue }
        )
    }

    var body: some View {
        Form {
            // The inline style lists the choices as rows with a checkmark
            // on the current one, and wraps at any text size.
            Section {
                Picker("Appearance", selection: appearance) {
                    ForEach(AppAppearance.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                SectionHeader("Appearance")
            }

            Section {
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    Label("Text size", systemImage: "textformat.size")
                    Text("Bloom follows your iPhone\u{2019}s text size. You can change it in iOS Settings under Display & Brightness.")
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Button("Open iOS Settings") {
                    NotificationManager.shared.openSettings()
                }
                .frame(minHeight: 44, alignment: .leading)
            } header: {
                SectionHeader("Text size")
            }
        }
        .navigationTitle("Display")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview("Light") {
    NavigationStack { SettingsDisplayView() }
        .preferredColorScheme(.light)
}

#Preview("Dark Accessibility 5") {
    NavigationStack { SettingsDisplayView() }
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
