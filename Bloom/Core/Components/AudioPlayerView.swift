import SwiftUI
import AVFoundation
import Combine

// Plays one voice memo at a time. A memo on a friend's note is only
// downloaded when play is first tapped.
@MainActor
final class VoicePlayer: NSObject, ObservableObject, AVAudioPlayerDelegate {
    enum State: Equatable {
        case idle
        case loading
        case playing
        case paused
        case failed(String)
    }

    enum Source {
        case local(URL)
        case friend(ownerUID: String, noteID: String)
    }

    @Published private(set) var state: State = .idle
    @Published private(set) var progress: Double = 0
    @Published private(set) var duration: TimeInterval

    private let source: Source
    private var player: AVAudioPlayer?
    private var ticker: Task<Void, Never>?

    init(source: Source, seconds: Int?) {
        self.source = source
        self.duration = TimeInterval(seconds ?? 0)
    }

    func toggle() {
        switch state {
        case .playing:
            pause()
        case .paused:
            resume()
        case .loading:
            break
        case .idle, .failed:
            Task { await start() }
        }
    }

    private func start() async {
        state = .loading
        let url: URL
        switch source {
        case .local(let localURL):
            url = localURL
        case .friend(let ownerUID, let noteID):
            switch await FriendAudioCache.shared.audio(ownerUID: ownerUID, noteID: noteID) {
            case .file(let cached): url = cached
            case .failed:
                state = .failed("Couldn\u{2019}t load this voice memo. Check your connection and tap to try again.")
                return
            }
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.delegate = self
            player.prepareToPlay()
            duration = player.duration
            self.player = player
            resume()
        } catch {
            state = .failed("This voice memo can\u{2019}t be played. Tap to try again.")
        }
    }

    private func resume() {
        guard let player else { return }
        guard AudioCoordinator.shared.begin(owner: self, mode: .playback, stop: { [weak self] in
            self?.pause()
        }) else {
            state = .failed("Couldn\u{2019}t start playback. Tap to try again.")
            return
        }
        player.play()
        state = .playing
        startTicker()
    }

    func pause() {
        guard state == .playing else { return }
        player?.pause()
        ticker?.cancel()
        state = .paused
        AudioCoordinator.shared.end(owner: self)
    }

    // Stops and rewinds, for when the row leaves the screen.
    func stop() {
        player?.stop()
        player = nil
        ticker?.cancel()
        progress = 0
        if state == .playing || state == .paused { state = .idle }
        AudioCoordinator.shared.end(owner: self)
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                guard let self, let player = self.player else { return }
                self.progress = player.duration > 0 ? player.currentTime / player.duration : 0
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
    }

    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.ticker?.cancel()
            self.progress = 0
            self.player = nil
            self.state = .idle
            AudioCoordinator.shared.end(owner: self)
        }
    }
}

// Play or pause, a progress bar and the length. Used wherever a note's
// memo is shown.
struct AudioPlayerView: View {
    @StateObject private var player: VoicePlayer
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(source: VoicePlayer.Source, seconds: Int?) {
        _player = StateObject(wrappedValue: VoicePlayer(source: source, seconds: seconds))
    }

    private var layout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private var isPlaying: Bool { player.state == .playing }

    private var lengthText: String { Self.format(player.duration) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            layout {
                Button {
                    player.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.largeTitle)
                        .frame(minWidth: 44, minHeight: 44)
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(buttonLabel)

                ProgressView(value: player.progress)
                    .accessibilityHidden(true)

                Text(statusText)
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }

            if case .failed(let message) = player.state {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onDisappear { player.stop() }
    }

    private var statusText: String {
        switch player.state {
        case .loading: return "Loading..."
        default: return lengthText
        }
    }

    private var buttonLabel: String {
        switch player.state {
        case .loading: return "Loading voice memo"
        case .playing: return "Pause voice memo, \(lengthText)"
        default: return "Play voice memo, \(lengthText)"
        }
    }

    // 0:42 style.
    static func format(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds.rounded()))
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}

// The memo on one of my own notes, if it has one.
struct NoteVoiceMemo: View {
    let note: Note

    var body: some View {
        if let url = note.audioURL {
            AudioPlayerView(source: .local(url), seconds: note.audioSeconds)
        }
    }
}

// The memo on a friend's shared note. Nothing is downloaded until
// play is tapped.
struct FriendVoiceMemo: View {
    let friendUID: String
    let note: FriendNote

    var body: some View {
        if note.hasAudio == true, let noteID = note.id {
            AudioPlayerView(source: .friend(ownerUID: friendUID, noteID: noteID), seconds: note.audioSeconds)
        }
    }
}
