import SwiftUI

// The rows of the composer's attachment strip, under the text editor.
// The movie or show uses the existing MediaDraftCard.

// A thumbnail of the attached photo with Replace and Remove. There is
// one photo per note, so Replace takes a new one over it.
struct PhotoAttachmentRow: View {
    let image: UIImage
    let onTakePhoto: () -> Void
    let onChoosePhoto: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxHeight: 200)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Attached photo")

            HStack(spacing: 16) {
                Menu {
                    Button("Take photo", systemImage: "camera", action: onTakePhoto)
                    Button("Choose photo", systemImage: "photo.on.rectangle", action: onChoosePhoto)
                } label: {
                    Text("Replace")
                        .frame(minHeight: 44)
                }
                .accessibilityLabel("Replace photo")

                Button("Remove", role: .destructive, action: onRemove)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Remove photo")
            }
            .buttonStyle(.borderless)
        }
    }
}

// A small player for the attached voice memo with Delete.
struct VoiceMemoAttachmentRow: View {
    let fileName: String
    let seconds: Int
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            AudioPlayerView(
                source: .local(FileManager.audioDirectory.appendingPathComponent(fileName)),
                seconds: seconds
            )
            .id(fileName)

            Button("Delete", systemImage: "trash", role: .destructive, action: onDelete)
                .buttonStyle(.borderless)
                .frame(minHeight: 44)
                .accessibilityLabel("Delete voice memo")
        }
    }
}

// Why the camera can't be used, in place, with Open Settings when that
// would help.
struct CameraNoticeRow: View {
    let notice: CameraNotice
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(notice.message, systemImage: "camera.badge.ellipsis")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                if notice.canOpenSettings {
                    Button("Open Settings") { CameraAccess.openSettings() }
                        .frame(minHeight: 44)
                }
                Button("Dismiss", action: onDismiss)
                    .frame(minHeight: 44)
                    .accessibilityLabel("Dismiss camera message")
            }
            .buttonStyle(.borderless)
        }
    }
}
