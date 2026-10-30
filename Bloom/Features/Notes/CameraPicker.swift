import SwiftUI
import AVFoundation
import UIKit
import UniformTypeIdentifiers

// A message about why the camera can't be used, shown inline in the
// composer. Open Settings is offered when the person can fix it there.
struct CameraNotice: Equatable {
    let message: String
    var canOpenSettings = false

    static let couldntUsePhoto = CameraNotice(message: "Couldn\u{2019}t use that photo. Try again.")
}

// Everything checked before the camera is presented. Never asks for
// permission until Take photo is tapped, and never touches the Photos
// library, so there is no Photos permission either.
enum CameraAccess {
    enum Outcome {
        case ready
        case blocked(CameraNotice)
    }

    private static var hasUsageDescription: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") as? String
        return !(value?.isEmpty ?? true)
    }

    @MainActor
    static func prepare() async -> Outcome {
        // The simulator has no camera.
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            return .blocked(CameraNotice(message: "No camera available here. Use Choose photo instead."))
        }

        // Asking without this key would crash the app.
        guard hasUsageDescription else {
            return .blocked(CameraNotice(message: "Camera access isn\u{2019}t set up in this build"))
        }

        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            return .ready
        case .notDetermined:
            if await AVCaptureDevice.requestAccess(for: .video) {
                return .ready
            }
            return .blocked(deniedNotice)
        case .denied:
            return .blocked(deniedNotice)
        case .restricted:
            return .blocked(CameraNotice(
                message: "The camera is restricted on this device. Use Choose photo instead.",
                canOpenSettings: true
            ))
        @unknown default:
            return .blocked(CameraNotice(message: "The camera can\u{2019}t be used right now. Use Choose photo instead."))
        }
    }

    private static var deniedNotice: CameraNotice {
        CameraNotice(
            message: "Camera access is off. Turn it on in Settings to take photos.",
            canOpenSettings: true
        )
    }

    @MainActor
    static func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// The system camera, presented full screen. It only hands back the
// picture, nothing is written to the Photos library.
struct CameraPicker: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    let onCancel: () -> Void
    let onFailure: () -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        // Setting .camera on a device without one would crash, so fail
        // quietly instead. The composer checks first, this is the backstop.
        if UIImagePickerController.isSourceTypeAvailable(.camera) {
            picker.sourceType = .camera
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
        } else {
            DispatchQueue.main.async { onFailure() }
        }
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var parent: CameraPicker

        init(parent: CameraPicker) {
            self.parent = parent
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            } else {
                parent.onFailure()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.onCancel()
        }
    }
}
