import SwiftUI

// The compact recording sheet the mic tool opens: record, stop, play,
// delete, a timer counting to the 60 second limit, and Save or Cancel.
// It uses the existing recorder and its permission handling. Nothing
// reaches the note until Save, and a recording that isn't saved is
// removed from disk.
struct VoiceMemoSheet: View {
    let onSave: (RecordedMemo) -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var recorder = VoiceMemoRecorder()
    @State private var pending: RecordedMemo?
    @State private var didSave = false

    private var limitText: String {
        AudioPlayerView.format(TimeInterval(VoiceMemoRecorder.limitSeconds))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    content

                    if let message = recorder.message {
                        Text(message)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding()
            }
            .navigationTitle("Voice Memo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        discardPending()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(pending == nil || recorder.isRecording)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // Cancel and Save are the ways out while there is something to lose.
        .interactiveDismissDisabled(recorder.isRecording || pending != nil)
        .onChange(of: recorder.finished) { _, memo in
            guard let memo else { return }
            // A new recording replaces the one waiting to be saved.
            discardPending()
            pending = memo
        }
        .onDisappear {
            recorder.stop(because: .discard)
            if !didSave { discardPending() }
        }
    }

    @ViewBuilder
    private var content: some View {
        if recorder.permission == .denied {
            VStack(spacing: 8) {
                Text("Microphone access is off")
                    .font(.subheadline)
                    .fontWeight(.medium)
                Text("Turn it on in Settings to record voice memos.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button("Open Settings") { recorder.openSettings() }
                    .buttonStyle(.bordered)
                    .frame(minHeight: 44)
            }
            .multilineTextAlignment(.center)
        } else if recorder.isRecording {
            VStack(spacing: 16) {
                Label {
                    Text("\(AudioPlayerView.format(recorder.elapsed)) of \(limitText)")
                        .font(.title2)
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "record.circle")
                        .foregroundStyle(.red)
                        .accessibilityHidden(true)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Recording, \(Int(recorder.elapsed)) seconds of \(VoiceMemoRecorder.limitSeconds)")

                Button {
                    recorder.stop()
                } label: {
                    Label("Stop", systemImage: "stop.circle.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Stop recording")
            }
        } else if let pending {
            VStack(spacing: 12) {
                AudioPlayerView(
                    source: .local(FileManager.audioDirectory.appendingPathComponent(pending.fileName)),
                    seconds: pending.seconds
                )
                .id(pending.fileName)

                HStack(spacing: 16) {
                    Button("Re-record", systemImage: "mic") { startRecording() }
                        .frame(minHeight: 44)
                        .accessibilityLabel("Record again")
                    Button("Delete", systemImage: "trash", role: .destructive) {
                        discardPending()
                    }
                    .frame(minHeight: 44)
                    .accessibilityLabel("Delete recording")
                }
                .buttonStyle(.borderless)
            }
        } else {
            VStack(spacing: 8) {
                Button {
                    startRecording()
                } label: {
                    Label("Record", systemImage: "mic.fill")
                        .frame(minHeight: 44)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityLabel("Record voice memo")
                .accessibilityHint("Records up to \(VoiceMemoRecorder.limitSeconds) seconds")

                Text("Up to \(limitText)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func startRecording() {
        Task { await recorder.start() }
    }

    private func save() {
        guard let pending else { return }
        didSave = true
        onSave(pending)
        dismiss()
    }

    // Removes the recording that was never saved onto a note.
    private func discardPending() {
        guard let old = pending else { return }
        try? FileManager.default.removeItem(at: FileManager.audioDirectory.appendingPathComponent(old.fileName))
        pending = nil
    }
}

#Preview {
    Text("Composer")
        .sheet(isPresented: .constant(true)) {
            VoiceMemoSheet { _ in }
        }
}
