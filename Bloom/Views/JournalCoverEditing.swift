import SwiftUI
import PhotosUI
import Combine

// Picks a photo for a book cover and saves it through JournalCoverStore,
// with a progress state and an error message. One editor per screen that
// can present a picker.
@MainActor
final class JournalCoverEditor: ObservableObject {
    @Published var isPickerPresented = false
    @Published var selection: PhotosPickerItem?
    @Published private(set) var isSaving = false
    @Published var errorMessage: String?

    private var key: String?

    // Opens the photo picker for one book.
    func choose(key: String) {
        self.key = key
        selection = nil
        isPickerPresented = true
    }

    func save(_ item: PhotosPickerItem) async {
        guard let key else { return }
        isSaving = true
        defer {
            isSaving = false
            selection = nil
        }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw JournalCoverStore.CoverError.unreadablePhoto
            }
            try await JournalCoverStore.shared.setCover(photoData: data, key: key)
        } catch let error as JournalCoverStore.CoverError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = JournalCoverStore.CoverError.unreadablePhoto.errorDescription
        }
    }

    func remove(key: String) {
        do {
            try JournalCoverStore.shared.removeCover(key: key)
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription
                ?? JournalCoverStore.CoverError.saveFailed.errorDescription
        }
    }
}

private struct JournalCoverEditing: ViewModifier {
    @ObservedObject var editor: JournalCoverEditor

    func body(content: Content) -> some View {
        content
            .photosPicker(isPresented: $editor.isPickerPresented, selection: $editor.selection, matching: .images)
            .onChange(of: editor.selection) { _, item in
                guard let item else { return }
                Task { await editor.save(item) }
            }
            .overlay {
                if editor.isSaving {
                    ProgressView("Saving cover")
                        .padding(24)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .alert(
                "Couldn\u{2019}t update the cover",
                isPresented: Binding(
                    get: { editor.errorMessage != nil },
                    set: { if !$0 { editor.errorMessage = nil } }
                )
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(editor.errorMessage ?? "")
            }
    }
}

extension View {
    func journalCoverEditing(_ editor: JournalCoverEditor) -> some View {
        modifier(JournalCoverEditing(editor: editor))
    }

    // Edit cover, Choose photo and Remove photo on a book, for my own journals only.
    @ViewBuilder
    func journalCoverMenu(
        key: String,
        canEdit: Bool,
        editor: JournalCoverEditor,
        covers: JournalCoverStore,
        edit: @escaping () -> Void
    ) -> some View {
        if canEdit {
            contextMenu {
                Button {
                    edit()
                } label: {
                    Label("Edit cover", systemImage: "paintpalette")
                }
                Button {
                    editor.choose(key: key)
                } label: {
                    Label("Choose photo", systemImage: "photo")
                }
                if covers.image(for: key) != nil {
                    Button(role: .destructive) {
                        editor.remove(key: key)
                    } label: {
                        Label("Remove photo", systemImage: "trash")
                    }
                }
            }
        } else {
            self
        }
    }
}

// The Edit cover sheet for a year or a month.
struct JournalCoverSheet: View {
    let key: String
    let title: String
    let subtitle: String
    // The colour used when nothing was picked, an index into the palette.
    let automaticIndex: Int
    var isCompact = false

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var covers = JournalCoverStore.shared
    @StateObject private var editor = JournalCoverEditor()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    BookCoverView(
                        title: title,
                        subtitle: subtitle,
                        coverImage: covers.image(for: key),
                        accent: covers.accent(for: key, automaticIndex: automaticIndex),
                        isCompact: isCompact
                    )
                    .frame(width: 180)
                    .padding(.top, 8)

                    VStack(spacing: 12) {
                        Button {
                            editor.choose(key: key)
                        } label: {
                            Label("Choose photo", systemImage: "photo")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                        if covers.image(for: key) != nil {
                            Button(role: .destructive) {
                                editor.remove(key: key)
                            } label: {
                                Label("Remove photo", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.large)
                        }
                    }

                    colourPicker

                    Text("Covers are saved on this device only. They aren\u{2019}t backed up, and your friends never see them.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding()
                .frame(maxWidth: 500)
                .frame(maxWidth: .infinity)
            }
            .navigationTitle("Edit cover")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .journalCoverEditing(editor)
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Colour

extension JournalCoverSheet {
    // The six theme colours, plus a way back to the book's own colour.
    fileprivate var colourPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Colour")
                .font(.headline)
                .accessibilityAddTraits(.isHeader)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 52), spacing: 12)], spacing: 12) {
                ForEach(Theme.Covers.palette.indices, id: \.self) { index in
                    let isSelected = covers.pickedColorIndex(for: key) == index
                    Button {
                        covers.setColorIndex(index, for: key)
                    } label: {
                        Circle()
                            .fill(Theme.Covers.palette[index])
                            .frame(width: 44, height: 44)
                            .overlay {
                                if isSelected {
                                    Image(systemName: "checkmark")
                                        .font(.body.bold())
                                        .foregroundStyle(Theme.Covers.text)
                                }
                            }
                            .overlay(Circle().strokeBorder(Color(.separator), lineWidth: 0.5))
                            .frame(minWidth: 52, minHeight: 52)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Theme.Covers.names[index])
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }

            if covers.pickedColorIndex(for: key) != nil {
                Button("Use automatic colour") {
                    covers.setColorIndex(nil, for: key)
                }
            }

            Text("The colour shows when the book has no photo.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
