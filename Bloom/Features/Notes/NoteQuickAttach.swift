import SwiftUI
import Combine
import PhotosUI
import SwiftData

// The icon row of a Today's Notes card: each tool changes the note it is
// on straight away. The changes themselves are made by
// NoteAttachmentEditing, the same code the composer saves with, and the
// camera checks are the composer's too (CameraAccess).
@MainActor
final class NoteQuickAttach: ObservableObject {
    let note: Note

    @Published var isShowingPhotoPicker = false
    @Published var isShowingCamera = false
    @Published var isShowingVoiceMemo = false
    @Published var isShowingMediaSearch = false
    @Published var entryToShow: MediaLogEntry?
    @Published var photoItem: PhotosPickerItem?
    // Why the camera can't open, shown inline on the card.
    @Published var notice: CameraNotice?

    init(note: Note) {
        self.note = note
    }

    // MARK: Opening a tool

    // Checks the camera first, so the system prompt only ever appears
    // after a tap, and shows the reason in place when it can't open.
    func takePhoto() {
        notice = nil
        Task {
            switch await CameraAccess.prepare() {
            case .ready:
                isShowingCamera = true
            case .blocked(let blocked):
                notice = blocked
                AccessibilityNotification.Announcement(blocked.message).post()
            }
        }
    }

    func choosePhoto() { isShowingPhotoPicker = true }

    func recordMemo() { isShowingVoiceMemo = true }

    // A note with a movie or show opens its entry, otherwise the search
    // and review flow starts.
    func openMedia() {
        if let entry = note.mediaLogEntry {
            entryToShow = entry
        } else {
            isShowingMediaSearch = true
        }
    }

    // MARK: Results

    func loadPickedPhoto() async {
        guard let item = photoItem else { return }
        defer { photoItem = nil }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            notice = .couldntUsePhoto
            return
        }
        replacePhoto(with: data)
    }

    func captured(_ image: UIImage) {
        isShowingCamera = false
        // The same path as a photo from the library.
        guard let data = image.jpegData(compressionQuality: 0.9) else {
            notice = .couldntUsePhoto
            return
        }
        replacePhoto(with: data)
    }

    func recorded(_ memo: RecordedMemo) {
        guard let context = note.modelContext else { return }
        NoteAttachmentEditing.setAudio(fileName: memo.fileName, seconds: memo.seconds, on: note)
        NoteAttachmentEditing.commit(note, in: context)
    }

    func chose(_ draft: MediaReviewDraft) {
        guard let context = note.modelContext else { return }
        NoteAttachmentEditing.setMedia(draft, on: note, in: context)
        NoteAttachmentEditing.commit(note, in: context)
    }

    // MARK: Removing

    func removePhoto() {
        guard let context = note.modelContext else { return }
        NoteAttachmentEditing.setPhoto(nil, on: note)
        NoteAttachmentEditing.commit(note, in: context)
    }

    func removeMemo() {
        guard let context = note.modelContext else { return }
        NoteAttachmentEditing.setAudio(fileName: nil, seconds: nil, on: note)
        NoteAttachmentEditing.commit(note, in: context)
    }

    func removeMedia() {
        guard let context = note.modelContext else { return }
        NoteAttachmentEditing.setMedia(nil, on: note, in: context)
        NoteAttachmentEditing.commit(note, in: context)
    }

    private func replacePhoto(with data: Data) {
        guard let context = note.modelContext else { return }
        notice = nil
        NoteAttachmentEditing.setPhoto(data, on: note)
        NoteAttachmentEditing.commit(note, in: context)
    }
}

// The pickers and sheets the tools open, attached once to a card.
private struct QuickAttachPresentations: ViewModifier {
    @ObservedObject var controller: NoteQuickAttach

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $controller.isShowingPhotoPicker, selection: $controller.photoItem, matching: .images)
            .task(id: controller.photoItem) { await controller.loadPickedPhoto() }
            .fullScreenCover(isPresented: $controller.isShowingCamera) {
                CameraPicker(
                    onCapture: { controller.captured($0) },
                    onCancel: { controller.isShowingCamera = false },
                    onFailure: {
                        controller.isShowingCamera = false
                        controller.notice = .couldntUsePhoto
                    }
                )
                .ignoresSafeArea()
            }
            .sheet(isPresented: $controller.isShowingVoiceMemo) {
                VoiceMemoSheet { controller.recorded($0) }
            }
            .sheet(isPresented: $controller.isShowingMediaSearch) {
                MediaSearchView { controller.chose($0) }
            }
            .sheet(item: $controller.entryToShow) { entry in
                MediaLogEntryDetailView(entry: entry)
            }
    }
}

extension View {
    func quickAttachPresentations(_ controller: NoteQuickAttach) -> some View {
        modifier(QuickAttachPresentations(controller: controller))
    }
}
