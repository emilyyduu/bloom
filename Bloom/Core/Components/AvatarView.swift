import SwiftUI
import PhotosUI

// A person's profile picture, or their initials on a pale circle when
// they don't have one. The picture is fetched once through AvatarCache,
// keyed by uid and avatarUpdatedAt, so a changed picture reloads and
// others don't download again. Pass `localImage` to show a picture that
// hasn't reached the cloud yet (my own new photo while it uploads).
struct AvatarView: View {
    let uid: String?
    let name: String
    let hasAvatar: Bool
    let avatarUpdatedAt: Date?
    var localImage: UIImage?
    private let maxSize: CGFloat?

    @ScaledMetric private var scaledSize: CGFloat
    @State private var loadedImage: UIImage?

    init(
        uid: String?,
        name: String,
        hasAvatar: Bool,
        avatarUpdatedAt: Date?,
        size: CGFloat,
        localImage: UIImage? = nil,
        relativeTo textStyle: Font.TextStyle = .body,
        maxSize: CGFloat? = nil
    ) {
        self.uid = uid
        self.name = name
        self.hasAvatar = hasAvatar
        self.avatarUpdatedAt = avatarUpdatedAt
        self.localImage = localImage
        self.maxSize = maxSize
        _scaledSize = ScaledMetric(wrappedValue: size, relativeTo: textStyle)
    }

    init(user: FirestoreUser, size: CGFloat, relativeTo textStyle: Font.TextStyle = .body) {
        self.init(
            uid: user.id,
            name: user.shownName,
            hasAvatar: user.hasAvatar ?? false,
            avatarUpdatedAt: user.avatarUpdatedAt,
            size: size,
            relativeTo: textStyle
        )
    }

    private struct LoadKey: Equatable {
        let uid: String?
        let hasAvatar: Bool
        let updatedAt: Date?
    }

    private var diameter: CGFloat {
        maxSize.map { min(scaledSize, $0) } ?? scaledSize
    }

    private var shownImage: UIImage? {
        localImage ?? (hasAvatar ? loadedImage : nil)
    }

    // Very small avatars only have room for one letter.
    private var initials: String {
        let letters = name
            .split(whereSeparator: \.isWhitespace)
            .prefix(diameter < 32 ? 1 : 2)
            .compactMap(\.first)
        return letters.isEmpty ? "?" : String(letters).uppercased()
    }

    var body: some View {
        ZStack {
            if let shownImage {
                Image(uiImage: shownImage)
                    .resizable()
                    .scaledToFill()
            } else {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                Text(initials)
                    .font(.system(size: diameter * 0.38, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(.isImage)
        .task(id: LoadKey(uid: uid, hasAvatar: hasAvatar, updatedAt: avatarUpdatedAt)) {
            // DEBUG sample friends have no avatar and never touch Firestore.
            guard hasAvatar, let uid, !uid.hasPrefix("sample-") else {
                loadedImage = nil
                return
            }
            loadedImage = await AvatarCache.shared.image(uid: uid, updatedAt: avatarUpdatedAt)
        }
    }
}

// My own avatar with a menu: Choose photo, Remove photo. Used on
// Profile and in Edit Profile; both read the same MyAvatar so they
// never disagree. Parents show `model.errorMessage` themselves.
struct EditableAvatar: View {
    @ObservedObject var model: MyAvatar
    let uid: String?
    let name: String
    var size: CGFloat = 96
    var relativeTo: Font.TextStyle = .largeTitle
    var maxSize: CGFloat?

    @State private var isPickerPresented = false
    @State private var pickerItem: PhotosPickerItem?

    var body: some View {
        // The picker is attached outside the Menu: a PhotosPicker inside
        // a Menu is dismissed along with the menu.
        Menu {
            Button {
                isPickerPresented = true
            } label: {
                Label("Choose photo", systemImage: "photo")
            }
            if model.hasAvatar {
                Button(role: .destructive) {
                    Task { await model.removePhoto() }
                } label: {
                    Label("Remove photo", systemImage: "trash")
                }
            }
        } label: {
            AvatarView(
                uid: uid,
                name: name,
                hasAvatar: model.hasAvatar,
                avatarUpdatedAt: model.updatedAt,
                size: size,
                localImage: model.localImage,
                relativeTo: relativeTo,
                maxSize: maxSize
            )
            .overlay {
                if model.isWorking {
                    ProgressView()
                        .padding(12)
                        .background(.regularMaterial, in: Circle())
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.caption)
                    .foregroundStyle(Color(.systemBackground))
                    .padding(7)
                    .background(Circle().fill(Color.accentColor))
                    .accessibilityHidden(true)
            }
        }
        .photosPicker(isPresented: $isPickerPresented, selection: $pickerItem, matching: .images)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            pickerItem = nil
            Task { await model.choosePhoto(item) }
        }
        .accessibilityLabel("Profile photo, \(name)")
        .accessibilityHint("Opens a menu to change or remove your photo")
    }
}
