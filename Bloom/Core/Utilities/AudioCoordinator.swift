import Foundation
import AVFoundation
import UIKit

// The one place that owns the shared audio session, so only one
// recording or playback is ever active. Whoever starts registers a
// stop closure; starting something else (or an interruption, an
// unplugged route or the app leaving the foreground) calls it. The
// session is deactivated as soon as the active owner ends.
@MainActor
final class AudioCoordinator {
    static let shared = AudioCoordinator()

    enum Mode {
        case record
        case playback
    }

    private var owner: AnyObject?
    private var stopCurrent: (() -> Void)?

    private init() {
        observe(AVAudioSession.interruptionNotification) { coordinator, note in
            let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
            if raw.flatMap(AVAudioSession.InterruptionType.init(rawValue:)) == .began {
                coordinator.stopCurrent?()
            }
        }
        observe(AVAudioSession.routeChangeNotification) { coordinator, note in
            // Headphones unplugged or a Bluetooth device lost.
            let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            if raw.flatMap(AVAudioSession.RouteChangeReason.init(rawValue:)) == .oldDeviceUnavailable {
                coordinator.stopCurrent?()
            }
        }
        // Without a background audio mode iOS suspends the app when the
        // screen locks, so finish cleanly while still running.
        observe(UIApplication.didEnterBackgroundNotification) { coordinator, _ in
            coordinator.stopCurrent?()
        }
    }

    private func observe(_ name: Notification.Name, handler: @escaping @MainActor (AudioCoordinator, Notification) -> Void) {
        Task { [weak self] in
            for await note in NotificationCenter.default.notifications(named: name) {
                guard let self else { return }
                handler(self, note)
            }
        }
    }

    // Takes over the session for `owner`, stopping whoever had it.
    // Returns false if the session couldn't be activated.
    func begin(owner newOwner: AnyObject, mode: Mode, stop: @escaping () -> Void) -> Bool {
        if let current = owner, current !== newOwner {
            stopCurrent?()
        }
        owner = newOwner
        stopCurrent = stop

        let session = AVAudioSession.sharedInstance()
        do {
            switch mode {
            case .record:
                try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            case .playback:
                try session.setCategory(.playback, mode: .default)
            }
            try session.setActive(true)
            return true
        } catch {
            end(owner: newOwner)
            return false
        }
    }

    // Releases the session if `owner` still holds it.
    func end(owner oldOwner: AnyObject) {
        guard owner === oldOwner else { return }
        owner = nil
        stopCurrent = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
