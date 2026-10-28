import SwiftUI
import SwiftData
import FirebaseAuth
import FirebaseFirestore

// The Profile tab: who I am, my friend count, quick actions, and the
// rows that used to be scattered across separate tabs (My Circle,
// Journals) or missing entirely (Settings).
struct ProfileView: View {
    private enum Destination: Hashable {
        case editProfile, myCircle, journals, settings
    }

    // One sheet(item:) drives every sheet, so they can never be asked to
    // present at the same time.
    private enum ProfileSheet: Identifiable {
        case friendSearch, shareProfile, note(Note)

        var id: String {
            switch self {
            case .friendSearch: return "friendSearch"
            case .shareProfile: return "shareProfile"
            case .note(let note): return "note-\(note.id.uuidString)"
            }
        }
    }

    @Query(filter: #Predicate<Note> { $0.isPinned && !$0.isDraft })
    private var pinnedNoteResults: [Note]

    @StateObject private var friendService = FriendService.shared
    @StateObject private var myAvatar = MyAvatar.shared

    @State private var path: [Destination] = []
    @State private var displayName: String = ""
    @State private var username: String = ""
    @State private var isLoadingProfile = true
    @State private var activeSheet: ProfileSheet?

    @ScaledMetric(relativeTo: .body) private var rowIconWidth: CGFloat = 28
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var shownName: String {
        let trimmed = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return username.isEmpty ? "Bloom User" : username
    }

    private var myUID: String? { Auth.auth().currentUser?.uid }

    // Newest pin first, at most the pin limit.
    private var pinnedNotes: [Note] {
        Array(
            pinnedNoteResults
                .sorted { ($0.pinnedAt ?? .distantPast) > ($1.pinnedAt ?? .distantPast) }
                .prefix(Note.pinLimit)
        )
    }

    private var friendCount: Int { friendService.friends.count }

    private var friendCountLabel: String {
        friendCount == 1 ? "friend" : "friends"
    }

    // In landscape (compact height) the header block sits on the left
    // and the buttons and rows on the right, inside the same
    // ScrollView so scroll position survives rotation.
    private var screenLayout: AnyLayout {
        isCompactHeight
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 24))
            : AnyLayout(VStackLayout(spacing: 20))
    }

    // At accessibility sizes the two buttons stack instead of
    // squeezing their labels.
    private var buttonLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 12))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        NavigationStack(path: $path) {
            VStack(spacing: 0) {
                ScreenHeader("Profile")

                ScrollView {
                    screenLayout {
                        headerBlock
                            .frame(maxWidth: isCompactHeight ? 260 : .infinity)

                        VStack(spacing: 20) {
                            actionButtons
                            searchButton
                            pinnedSection
                            rowsCard
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .padding(.bottom, 24)
                    .frame(maxWidth: isCompactHeight ? 900 : 700)
                    .frame(maxWidth: .infinity)
                }
            }
            // Matches the rest of the root screens, so the clear area
            // behind the header isn't a different colour than the
            // content beneath it.
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Profile")
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .editProfile:
                    EditProfileView(displayName: displayName, username: username) { newDisplayName, newUsername in
                        displayName = newDisplayName
                        username = newUsername
                    }
                case .myCircle:
                    MyCircleView()
                case .journals:
                    MonthlyJournalsListView()
                case .settings:
                    SettingsView()
                }
            }
            .sheet(item: $activeSheet) { sheet in
                switch sheet {
                case .friendSearch:
                    AddFriendView(startsWithSearchFocused: true)
                case .shareProfile:
                    ShareProfileSheet(uid: myUID ?? "", displayName: shownName, username: username)
                case .note(let note):
                    NoteDetailSheet(note: note)
                }
            }
            .task {
                friendService.startListening()
                await loadProfile()
            }
        }
    }

    // MARK: - Header

    private var headerBlock: some View {
        VStack(spacing: 12) {
            EditableAvatar(
                model: myAvatar,
                uid: myUID,
                name: shownName,
                size: 96,
                relativeTo: .largeTitle,
                maxSize: isCompactHeight ? 80 : 140
            )

            FormErrorText(message: myAvatar.errorMessage)
                .multilineTextAlignment(.center)

            VStack(spacing: 2) {
                if isLoadingProfile {
                    Text("Loading...")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundStyle(.secondary)
                } else {
                    Text(shownName)
                        .font(.title2)
                        .fontWeight(.bold)
                    if !username.isEmpty {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .multilineTextAlignment(.center)
            .accessibilityElement(children: .combine)

            friendsButton
        }
        .frame(maxWidth: .infinity)
    }

    private var friendsButton: some View {
        Button {
            path.append(.myCircle)
        } label: {
            HStack(spacing: 4) {
                Text("\(friendCount)")
                    .fontWeight(.bold)
                Text(friendCountLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.subheadline)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(friendCount) \(friendCountLabel), opens your circle")
    }

    // MARK: - Actions

    private var actionButtons: some View {
        buttonLayout {
            Button {
                path.append(.editProfile)
            } label: {
                Text("Edit profile")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isLoadingProfile)

            Button {
                activeSheet = .shareProfile
            } label: {
                Text("Share profile")
                    .frame(maxWidth: .infinity)
            }
            .disabled(isLoadingProfile || username.isEmpty || myUID == nil)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
    }

    // Looks like a text field but is a button: tapping opens Add Friend
    // with its own search field already active.
    private var searchButton: some View {
        Button {
            activeSheet = .friendSearch
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                Text("Search for friends")
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(10)
            .frame(minHeight: 44)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Pinned

    // Up to three pinned notes, newest pin first. Tapping one opens the
    // full note; press and hold offers Unpin.
    private var pinnedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader("Pinned")
                .accessibilityAddTraits(.isHeader)

            if pinnedNotes.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "pin")
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text("Nothing pinned yet. Press and hold a note, then choose Pin to profile.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(16)
                .profileCardBackground()
            } else {
                ForEach(pinnedNotes) { note in
                    Button {
                        activeSheet = .note(note)
                    } label: {
                        PinnedNoteCard(note: note)
                    }
                    .buttonStyle(.plain)
                    .notePinActions(note)
                }
            }
        }
    }

    // MARK: - Rows

    private var rowsCard: some View {
        VStack(spacing: 0) {
            row("My Circle", systemImage: "person.2", destination: .myCircle, badge: friendService.pendingIncoming.count)
            Divider().padding(.leading, 16)
            row("Your Journals", systemImage: "book.closed", destination: .journals)
            Divider().padding(.leading, 16)
            row("Settings", systemImage: "gear", destination: .settings)
        }
        .profileCardBackground()
    }

    private func row(_ title: String, systemImage: String, destination: Destination, badge: Int = 0) -> some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                // A fixed icon column keeps the titles aligned, since
                // the SF Symbols differ in width.
                Image(systemName: systemImage)
                    .frame(width: rowIconWidth)
                    .accessibilityHidden(true)
                Text(title)
                Spacer(minLength: 8)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(Color(.systemBackground))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.accentColor))
                        .accessibilityHidden(true)
                }
                Image(systemName: "chevron.right")
                    .font(.footnote)
                    .fontWeight(.semibold)
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityValue(badge > 0 ? "\(badge) pending \(badge == 1 ? "request" : "requests")" : "")
    }

    // MARK: - Loading

    private func loadProfile() async {
        guard let uid = Auth.auth().currentUser?.uid else {
            isLoadingProfile = false
            return
        }

        let docRef = Firestore.firestore().collection("users").document(uid)
        do {
            let snapshot = try await docRef.getDocument()
            let data = snapshot.data()
            username = data?["username"] as? String ?? ""
            displayName = data?["displayName"] as? String ?? ""
            myAvatar.load(
                hasAvatar: data?["hasAvatar"] as? Bool ?? false,
                updatedAt: (data?["avatarUpdatedAt"] as? Timestamp)?.dateValue()
            )

            if !username.isEmpty, data?["usernameLower"] == nil || data?["displayName"] == nil {
                await backfillProfile(docRef: docRef, username: username, displayName: displayName)
            }
        } catch {
            username = ""
            displayName = ""
        }
        isLoadingProfile = false
    }

    // Older profiles were created before usernameLower and displayName
    // existed, and some may still carry a leftover "email" field from
    // before the Firestore rules started rejecting any extra field on
    // this document. All of it is fixed here, the moment the signed-in
    // user's own profile is loaded. displayName, username and
    // usernameLower are always written together, and an existing
    // displayName is never overwritten. Failures only print in DEBUG
    // since this is a best-effort migration, not something the user can
    // act on.
    private func backfillProfile(docRef: DocumentReference, username: String, displayName: String) async {
        let newDisplayName = displayName.isEmpty ? username : displayName
        do {
            try await docRef.updateData([
                "displayName": newDisplayName,
                "username": username,
                "usernameLower": username.lowercased(),
                "email": FieldValue.delete(),
            ])
            self.displayName = newDisplayName
        } catch {
            #if DEBUG
            print("ProfileView: failed to backfill displayName and usernameLower for existing profile: \(error)")
            #endif
        }
    }
}

// MARK: - Supporting views

// One of my pinned notes: date, a few lines of text, a photo thumbnail
// if it has one, and a reminder when friends can't see it yet.
private struct PinnedNoteCard: View {
    let note: Note

    @ScaledMetric(relativeTo: .body) private var thumbnailSize: CGFloat = 64

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(note.createdAt, format: .dateTime.day().month(.abbreviated).year())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(note.text)
                        .font(.subheadline)
                        .lineLimit(4)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if let photo = note.photo {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                        .frame(width: thumbnailSize, height: thumbnailSize)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .accessibilityLabel("Photo")
                }
            }

            if !note.sharedWithFriends {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Only you", systemImage: "lock.fill")
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("Share this note so friends can see it on your profile.")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .profileCardBackground()
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the full note")
    }
}

private extension View {
    // The rounded card used for Profile's Pinned placeholder and rows,
    // matching the cards on Greenhouse.
    func profileCardBackground() -> some View {
        self
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1))
    }
}

#Preview("Light") {
    ProfileView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    ProfileView()
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type - Large") {
    ProfileView()
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Dynamic Type - XXX Large") {
    ProfileView()
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Dynamic Type - Accessibility 5") {
    ProfileView()
        .modelContainer(PreviewContainer.shared)
        .environment(\.dynamicTypeSize, .accessibility5)
}

#Preview("Landscape", traits: .landscapeLeft) {
    ProfileView()
        .modelContainer(PreviewContainer.shared)
}
