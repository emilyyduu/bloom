import Foundation
import SwiftData
import UIKit

extension Note {
    static func createDraft(
        in context: ModelContext,
        text: String,
        photoFileName: String? = nil
    ) -> Note {
        let note = Note(text: text, photoFileName: photoFileName)
        context.insert(note)
        return note
    }

    var hasPhoto: Bool {
        photoFileName != nil
    }

    var photo: UIImage? {
        guard let fileName = photoFileName else { return nil }
        let url = FileManager.documentsDirectory.appendingPathComponent(fileName)
        return UIImage(contentsOfFile: url.path)
    }

    var hasAudio: Bool {
        audioURL != nil
    }

    // The memo file, only if it still exists on disk.
    var audioURL: URL? {
        guard let audioFileName else { return nil }
        let url = FileManager.audioDirectory.appendingPathComponent(audioFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // Removes the local memo file. Doesn't touch the fields or the
    // cloud backup, callers decide that.
    func deleteAudioFile() {
        guard let audioFileName else { return }
        try? FileManager.default.removeItem(at: FileManager.audioDirectory.appendingPathComponent(audioFileName))
    }

    static let pinLimit = 3

    // DEBUG sample history notes start with this. In release builds no
    // note is ever a sample, so a real note can't be affected.
    static let samplePrefix = "Sample: "

    // Sample notes are never uploaded, shared or pinned.
    var isSample: Bool {
        #if DEBUG
        text.hasPrefix(Self.samplePrefix)
        #else
        false
        #endif
    }

    // How many posted notes are pinned right now.
    static func pinnedCount(in context: ModelContext) -> Int {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isPinned && !$0.isDraft })
        return (try? context.fetchCount(descriptor)) ?? 0
    }

    // Only posted notes can be pinned. If a draft somehow carries a pin,
    // this clears it and queues the note to re-upload without one.
    static func unpinDrafts(in context: ModelContext) {
        let descriptor = FetchDescriptor<Note>(predicate: #Predicate { $0.isPinned && $0.isDraft })
        guard let drafts = try? context.fetch(descriptor), !drafts.isEmpty else { return }
        for draft in drafts {
            draft.isPinned = false
            draft.pinnedAt = nil
            draft.syncedAt = nil
        }
        try? context.save()
    }

    // Used by TodaysNotesView and HomeView, both of which page through
    // today's saved notes in creation order.
    static func todaysNotesDescriptor() -> FetchDescriptor<Note> {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let endOfDay = Calendar.current.date(byAdding: .day, value: 1, to: startOfDay) ?? startOfDay

        return FetchDescriptor<Note>(
            predicate: #Predicate { note in
                note.createdAt >= startOfDay && note.createdAt < endOfDay && !note.isDraft
            },
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
    }
}

extension FileManager {
    static var documentsDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }

    // Documents/audio, where voice memos live as <uuid>.m4a.
    static var audioDirectory: URL {
        documentsDirectory.appendingPathComponent("audio", isDirectory: true)
    }

    // A fresh memo file name, with the audio folder created if needed.
    static func makeAudioFileName() throws -> String {
        try FileManager.default.createDirectory(at: audioDirectory, withIntermediateDirectories: true)
        return "\(UUID().uuidString).m4a"
    }

    // Saves downloaded memo bytes into Documents/audio and returns the
    // file name, ready to store in Note.audioFileName.
    static func writeAudioData(_ data: Data) throws -> String {
        let fileName = try makeAudioFileName()
        try data.write(to: audioDirectory.appendingPathComponent(fileName))
        return fileName
    }

    // Saves photo bytes into Documents under a fresh name and returns
    // that file name, ready to store in Note.photoFileName.
    static func writePhotoData(_ data: Data) throws -> String {
        let fileName = "\(UUID().uuidString).jpg"
        try data.write(to: documentsDirectory.appendingPathComponent(fileName))
        return fileName
    }
}
