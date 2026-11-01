import Foundation
import Combine
import SwiftUI
import PhotosUI
import FirebaseAuth

// The signed-in user's own profile picture, shared by Profile and Edit
// Profile so both always show the same thing. A newly chosen photo is
// shown straight away from a local copy while it uploads in the
// background; if the upload fails the old picture comes back and an
// error message is set.
@MainActor
final class MyAvatar: ObservableObject {
    static let shared = MyAvatar()
    private init() {}

    @Published private(set) var hasAvatar = false
    @Published private(set) var updatedAt: Date?
    // The exact bytes last uploaded, decoded, so my own picture shows
    // instantly and without a download.
    @Published private(set) var localImage: UIImage?
    @Published private(set) var isWorking = false
    @Published var errorMessage: String?

    private let store: AvatarStore = AvatarStores.current

    private var uid: String? { Auth.auth().currentUser?.uid }

    // Bumped on sign out so an upload or removal still in flight for the
    // previous account can't change the next account's picture state.
    private var generation = 0

    // Back to the signed-out state, called when the account changes.
    func reset() {
        generation += 1
        hasAvatar = false
        updatedAt = nil
        localImage = nil
        isWorking = false
        errorMessage = nil
    }

    // Called when my profile document is loaded. Skipped while a change
    // is in flight so it can't undo what was just chosen.
    func load(hasAvatar: Bool, updatedAt: Date?) {
        guard !isWorking else { return }
        self.hasAvatar = hasAvatar
        self.updatedAt = updatedAt
        localImage = nil
    }

    func choosePhoto(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Couldn't load that photo. Try another."
            return
        }
        await setPhoto(image)
    }

    private func setPhoto(_ image: UIImage) async {
        guard let uid, !isWorking else { return }
        guard let data = AvatarProcessor.uploadData(from: image), let processed = UIImage(data: data) else {
            errorMessage = "That photo couldn't be prepared. Try a different one."
            return
        }

        let previousImage = localImage
        let startedGeneration = generation
        localImage = processed
        errorMessage = nil
        isWorking = true
        do {
            let date = try await store.upload(data, uid: uid)
            await AvatarCache.shared.save(data, uid: uid, updatedAt: date)
            guard startedGeneration == generation else { return }
            hasAvatar = true
            updatedAt = date
        } catch {
            guard startedGeneration == generation else { return }
            localImage = previousImage
            errorMessage = "Couldn't update your photo. Check your connection and try again."
        }
        isWorking = false
    }

    func removePhoto() async {
        guard let uid, !isWorking else { return }

        let previousImage = localImage
        let previousHasAvatar = hasAvatar
        let startedGeneration = generation
        localImage = nil
        hasAvatar = false
        errorMessage = nil
        isWorking = true
        do {
            try await store.remove(uid: uid)
        } catch {
            guard startedGeneration == generation else { return }
            localImage = previousImage
            hasAvatar = previousHasAvatar
            errorMessage = "Couldn't remove your photo. Check your connection and try again."
        }
        guard startedGeneration == generation else { return }
        isWorking = false
    }
}
