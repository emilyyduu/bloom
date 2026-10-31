import SwiftUI
import SwiftData
import FirebaseAuth
import AVFoundation
import Contacts
import Photos
import UserNotifications

// How one iOS permission stands, in the words Settings shows.
enum PermissionStatus {
    case allowed, limited, notAsked, denied, restricted

    var text: String {
        switch self {
        case .allowed: return "Allowed"
        case .limited: return "Limited"
        case .notAsked: return "Not asked"
        case .denied: return "Denied"
        case .restricted: return "Restricted"
        }
    }
}

// Reads each permission without ever prompting for it.
@MainActor
enum PermissionReader {
    static func notifications() -> PermissionStatus {
        switch NotificationManager.shared.authorizationStatus {
        case .authorized, .provisional, .ephemeral: return .allowed
        case .denied: return .denied
        default: return .notAsked
        }
    }

    static func contacts() -> PermissionStatus {
        let status = CNContactStore.authorizationStatus(for: .contacts)
        if #available(iOS 18, *), status == .limited { return .limited }
        switch status {
        case .authorized: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notAsked
        }
    }

    static func camera() -> PermissionStatus {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .allowed
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notAsked
        }
    }

    static func microphone() -> PermissionStatus {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .allowed
        case .denied: return .denied
        default: return .notAsked
        }
    }

    static func photos() -> PermissionStatus {
        switch PHPhotoLibrary.authorizationStatus(for: .readWrite) {
        case .authorized: return .allowed
        case .limited: return .limited
        case .denied: return .denied
        case .restricted: return .restricted
        default: return .notAsked
        }
    }
}

// Settings > Privacy: who sees my notes, what iOS lets Bloom use, and the
// backup of my notes.
struct SettingsPrivacyView: View {
    @Query(filter: #Predicate<Note> { $0.syncedAt == nil }) private var unsyncedNotes: [Note]
    @Query(filter: #Predicate<Note> { !$0.isDraft }) private var postedNotes: [Note]
    @Query(filter: #Predicate<Note> { !$0.isDraft && $0.sharedWithFriends }) private var sharedNotes: [Note]

    @Environment(\.modelContext) private var context
    @Environment(\.scenePhase) private var scenePhase

    // Per account, see AccountDefaults.
    @AppStorage private var shareNewNotesWithFriends: Bool
    @AppStorage private var hasShownShareNewNotesConfirmation: Bool

    @State private var isShowingShareNewNotesConfirmation = false
    @State private var isShowingShareAllConfirmation = false
    @State private var isShowingStopSharingAllConfirmation = false
    @State private var isBulkUpdatingSharing = false
    @State private var isBackingUp = false
    @State private var permissions = PermissionSnapshot()

    // The statuses as of the last time the screen appeared or Bloom
    // became active, since they can change in iOS Settings.
    private struct PermissionSnapshot {
        var notifications = PermissionStatus.notAsked
        var contacts = PermissionStatus.notAsked
        var camera = PermissionStatus.notAsked
        var microphone = PermissionStatus.notAsked
        var photos = PermissionStatus.notAsked
    }

    init() {
        _shareNewNotesWithFriends = AppStorage(
            wrappedValue: false, AccountDefaults.key(AccountDefaults.shareNewNotesBase)
        )
        _hasShownShareNewNotesConfirmation = AppStorage(
            wrappedValue: false, AccountDefaults.key(AccountDefaults.shareNewNotesConfirmationBase)
        )
    }

    private static let sharingSummary =
        "Friends can see the notes you share on the day you post them, and your pinned notes."

    // Notes still waiting on a backup for the signed-in account: ones
    // not yet stamped with an owner, plus ones already stamped with
    // this uid. A note left over from a different account on this
    // device never counts here, syncPending won't touch it either.
    private var pendingBackupCount: Int {
        let uid = Auth.auth().currentUser?.uid
        return unsyncedNotes.filter { $0.ownerUID == nil || $0.ownerUID == uid }.count
    }

    private var backupStatusText: String {
        pendingBackupCount == 0
            ? "All notes backed up"
            : "\(pendingBackupCount) note\(pendingBackupCount == 1 ? "" : "s") waiting"
    }

    var body: some View {
        Form {
            sharingSection
            permissionsSection
            dataSection
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .navigationTitle("Privacy")
        .navigationBarTitleDisplayMode(.inline)
        .refreshesNotificationPermission()
        .task { await reloadPermissions() }
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            Task { await reloadPermissions() }
        }
        .alert(
            "Share new notes with friends",
            isPresented: $isShowingShareNewNotesConfirmation
        ) {
            Button("OK") { hasShownShareNewNotesConfirmation = true }
        } message: {
            Text(Self.sharingSummary)
        }
        .confirmationDialog(
            "Share all \(postedNotes.count) note\(postedNotes.count == 1 ? "" : "s")?",
            isPresented: $isShowingShareAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Share All") { bulkSetSharing(true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(Self.sharingSummary) Older notes stay hidden from them unless you pin them.")
        }
        .confirmationDialog(
            "Stop sharing \(sharedNotes.count) note\(sharedNotes.count == 1 ? "" : "s")?",
            isPresented: $isShowingStopSharingAllConfirmation,
            titleVisibility: .visible
        ) {
            Button("Stop Sharing", role: .destructive) { bulkSetSharing(false) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your friends will no longer see these notes, including any you pinned.")
        }
    }

    // MARK: - Sharing

    private var sharingSection: some View {
        Section {
            Toggle("Share new notes with friends", isOn: $shareNewNotesWithFriends)
                .onChange(of: shareNewNotesWithFriends) { _, isOn in
                    guard isOn, !hasShownShareNewNotesConfirmation else { return }
                    isShowingShareNewNotesConfirmation = true
                }

            Button("Share all my past notes") {
                isShowingShareAllConfirmation = true
            }
            .disabled(isBulkUpdatingSharing || postedNotes.isEmpty)
            .frame(minHeight: 44, alignment: .leading)

            Button("Stop sharing all notes", role: .destructive) {
                isShowingStopSharingAllConfirmation = true
            }
            .disabled(isBulkUpdatingSharing || sharedNotes.isEmpty)
            .frame(minHeight: 44, alignment: .leading)
        } header: {
            SectionHeader("Sharing")
        } footer: {
            Text(Self.sharingSummary)
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        Section {
            permissionRow("Notifications", systemImage: "bell", status: permissions.notifications)
            permissionRow("Contacts", systemImage: "person.crop.circle", status: permissions.contacts)
            permissionRow("Camera", systemImage: "camera", status: permissions.camera)
            permissionRow("Microphone", systemImage: "mic", status: permissions.microphone)
            permissionRow("Photos", systemImage: "photo", status: permissions.photos)
        } header: {
            SectionHeader("Permissions")
        } footer: {
            Text("Bloom only asks when you use a feature that needs it. Choosing a photo does not need access to your library.")
        }
    }

    private func permissionRow(_ title: String, systemImage: String, status: PermissionStatus) -> some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            LabeledContent {
                Text(status.text)
            } label: {
                Label(title, systemImage: systemImage)
            }
            if status == .denied {
                Button("Open iOS Settings") { NotificationManager.shared.openSettings() }
            }
        }
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    // MARK: - Data

    private var dataSection: some View {
        Section {
            LabeledContent {
                Text(backupStatusText)
            } label: {
                Label("Backup", systemImage: "icloud")
            }
            Button("Back up now") { backUpNow() }
                .disabled(isBackingUp || pendingBackupCount == 0)
                .frame(minHeight: 44, alignment: .leading)
        } header: {
            SectionHeader("Data")
        }
    }

    // MARK: - Actions

    private func reloadPermissions() async {
        await NotificationManager.shared.refresh()
        permissions = PermissionSnapshot(
            notifications: PermissionReader.notifications(),
            contacts: PermissionReader.contacts(),
            camera: PermissionReader.camera(),
            microphone: PermissionReader.microphone(),
            photos: PermissionReader.photos()
        )
    }

    private func backUpNow() {
        guard !isBackingUp else { return }
        isBackingUp = true
        Task {
            await NoteSyncService.shared.syncPending(context: context)
            isBackingUp = false
        }
    }

    private func bulkSetSharing(_ isShared: Bool) {
        guard !isBulkUpdatingSharing else { return }
        isBulkUpdatingSharing = true
        Task {
            await NoteSyncService.shared.setSharedWithFriendsForAllNotes(isShared, context: context)
            isBulkUpdatingSharing = false
        }
    }
}

#Preview("Light") {
    NavigationStack { SettingsPrivacyView() }
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.light)
}

#Preview("Dark Accessibility 5") {
    NavigationStack { SettingsPrivacyView() }
        .modelContainer(PreviewContainer.shared)
        .preferredColorScheme(.dark)
        .environment(\.dynamicTypeSize, .accessibility5)
}
