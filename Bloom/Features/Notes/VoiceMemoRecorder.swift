import Foundation
import AVFoundation
import Combine
import UIKit

// A finished recording, handed to the composer.
struct RecordedMemo: Equatable {
    let id = UUID()
    let fileName: String
    let seconds: Int
}

// Records one voice memo at a time for the composer: AAC in m4a, mono,
// 22050 Hz, about 32 kbps, at most 60 seconds (roughly 240 KB). It
// never asks for microphone permission until Record is tapped.
@MainActor
final class VoiceMemoRecorder: ObservableObject {
    enum Permission {
        case notAsked
        case granted
        case denied
        // The build has no NSMicrophoneUsageDescription, so asking
        // would crash the app.
        case notConfigured
    }

    static let limitSeconds = AudioLimits.maxSeconds

    @Published private(set) var isRecording = false
    @Published private(set) var elapsed: TimeInterval = 0
    @Published private(set) var permission: Permission = .notAsked
    @Published var message: String?
    @Published private(set) var finished: RecordedMemo?

    private var recorder: AVAudioRecorder?
    private var currentFileName: String?
    private var ticker: Task<Void, Never>?

    private static let settings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 22_050,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    init() {
        refreshPermission()
    }

    private static var hasUsageDescription: Bool {
        let value = Bundle.main.object(forInfoDictionaryKey: "NSMicrophoneUsageDescription") as? String
        return !(value?.isEmpty ?? true)
    }

    // Reads the current state without ever showing the system prompt.
    func refreshPermission() {
        guard Self.hasUsageDescription else {
            permission = .notConfigured
            return
        }
        switch AVAudioApplication.shared.recordPermission {
        case .granted: permission = .granted
        case .denied: permission = .denied
        default: permission = .notAsked
        }
    }

    // The Record tap. Asks for permission here, the first time only.
    func start() async {
        message = nil
        refreshPermission()

        switch permission {
        case .notConfigured:
            message = "Microphone access isn\u{2019}t set up in this build"
            return
        case .denied:
            return
        case .notAsked:
            guard await AVAudioApplication.requestRecordPermission() else {
                refreshPermission()
                return
            }
            refreshPermission()
        case .granted:
            break
        }

        beginRecording()
    }

    private func beginRecording() {
        guard !isRecording else { return }
        guard AudioCoordinator.shared.begin(owner: self, mode: .record, stop: { [weak self] in
            self?.stop(because: .interrupted)
        }) else {
            message = "Couldn\u{2019}t start recording. Try again."
            return
        }

        do {
            let fileName = try FileManager.makeAudioFileName()
            let url = FileManager.audioDirectory.appendingPathComponent(fileName)
            let recorder = try AVAudioRecorder(url: url, settings: Self.settings)
            guard recorder.prepareToRecord(), recorder.record() else {
                throw CocoaError(.fileWriteUnknown)
            }
            self.recorder = recorder
            currentFileName = fileName
            elapsed = 0
            isRecording = true
            startTicker()
        } catch {
            message = "Couldn\u{2019}t start recording. Try again."
            AudioCoordinator.shared.end(owner: self)
        }
    }

    // Updates the timer and stops at the limit.
    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let recorder = self.recorder, self.isRecording else { return }
                self.elapsed = min(recorder.currentTime, TimeInterval(Self.limitSeconds))
                if recorder.currentTime >= TimeInterval(Self.limitSeconds) {
                    self.stop(because: .limit)
                    return
                }
            }
        }
    }

    enum StopReason {
        case user
        case limit
        case interrupted
        // Throw the recording away, for when the composer closes.
        case discard
    }

    func stop(because reason: StopReason = .user) {
        guard isRecording, let recorder, let fileName = currentFileName else { return }
        ticker?.cancel()
        ticker = nil

        let duration = recorder.currentTime
        recorder.stop()
        self.recorder = nil
        currentFileName = nil
        isRecording = false
        AudioCoordinator.shared.end(owner: self)

        let url = FileManager.audioDirectory.appendingPathComponent(fileName)
        if reason == .discard || duration < 1 {
            try? FileManager.default.removeItem(at: url)
            if reason != .discard { message = "That was too short. Tap Record and speak for at least a second." }
            return
        }

        elapsed = 0
        finished = RecordedMemo(fileName: fileName, seconds: min(Self.limitSeconds, Int(duration.rounded())))

        switch reason {
        case .limit:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            message = "You reached the \(Self.limitSeconds) second limit."
        case .interrupted:
            message = "Recording stopped because Bloom was interrupted. What you recorded was kept."
        default:
            break
        }
    }

    func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
