import SwiftUI
import CoreImage
import CoreImage.CIFilterBuiltins

// My profile as a QR code and a link, so a friend can add me by
// scanning or tapping instead of searching. The link is
// bloom://add/{uid}, see ProfileLink.
struct ShareProfileSheet: View {
    let uid: String
    let displayName: String
    let username: String

    @Environment(\.dismiss) private var dismiss
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject private var myAvatar = MyAvatar.shared

    @State private var didCopy = false

    private let url: URL?
    private let qrImage: UIImage?

    init(uid: String, displayName: String, username: String) {
        self.uid = uid
        self.displayName = displayName
        self.username = username
        let url = ProfileLink.url(forUID: uid)
        self.url = url
        self.qrImage = url.flatMap { QRCode.image(for: $0.absoluteString) }
    }

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    // In landscape (below) the QR code sits beside the details so
    // neither has to scroll away.
    var body: some View {
        NavigationStack {
            ScrollView {
                Group {
                    if isCompactHeight {
                        HStack(alignment: .center, spacing: 32) {
                            qrCode
                            VStack(spacing: 20) {
                                identity
                                actions
                            }
                        }
                    } else {
                        VStack(spacing: 20) {
                            identity
                            qrCode
                            actions
                        }
                    }
                }
                .padding()
                .frame(maxWidth: 700)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Share Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var identity: some View {
        VStack(spacing: 10) {
            AvatarView(
                uid: uid,
                name: displayName,
                hasAvatar: myAvatar.hasAvatar,
                avatarUpdatedAt: myAvatar.updatedAt,
                size: 72,
                localImage: myAvatar.localImage,
                relativeTo: .largeTitle,
                maxSize: 120
            )
            .accessibilityHidden(true)

            VStack(spacing: 2) {
                Text(displayName)
                    .font(.title2)
                    .fontWeight(.bold)
                Text("@\(username)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)
        }
    }

    @ViewBuilder
    private var qrCode: some View {
        if let qrImage {
            // QR codes need dark modules on a light background to scan,
            // so this stays black on white in dark mode too.
            Image(uiImage: qrImage)
                .interpolation(.none)
                .resizable()
                .scaledToFit()
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color.white))
                .frame(maxWidth: 260)
                .accessibilityLabel("QR code for your Bloom profile")
                .accessibilityHint("Friends can scan it to add you")
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            if let url {
                ShareLink(item: url, message: Text("Add me on Bloom! I'm @\(username)")) {
                    Label("Share link", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            }

            Button {
                UIPasteboard.general.string = username
                didCopy = true
                Task {
                    try? await Task.sleep(for: .seconds(2))
                    didCopy = false
                }
            } label: {
                Label(
                    didCopy ? "Copied" : "Copy username",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .accessibilityValue(didCopy ? "Copied to the clipboard" : "")
        }
        .frame(maxWidth: 400)
    }
}

// Draws a QR code as crisp square modules. The generator's output is
// one pixel per module, so it's scaled up by a whole number with
// nearest neighbour sampling; smoothing would blur the edges.
enum QRCode {
    static func image(for text: String, moduleScale: CGFloat = 10) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage else { return nil }
        let scaled = output
            .samplingNearest()
            .transformed(by: CGAffineTransform(scaleX: moduleScale, y: moduleScale))

        guard let cgImage = CIContext().createCGImage(scaled, from: scaled.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

#Preview {
    ShareProfileSheet(uid: "preview1234", displayName: "Allison Chen", username: "allison")
}
