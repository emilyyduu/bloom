import SwiftUI
import FirebaseAuth
import FirebaseFirestore

// Shown when a bloom://add/{uid} link is opened: who it points to and
// the right action for how we're already connected. Sending and
// accepting reuse FriendService, so the request rules are unchanged.
struct AddByLinkSheet: View {
    let uid: String

    @Environment(\.dismiss) private var dismiss
    @StateObject private var friendService = FriendService.shared

    private enum LoadState {
        case loading
        case loaded(FirestoreUser)
        case notFound
        case ownProfile
        case failed
    }

    @State private var state: LoadState = .loading
    @State private var requestErrorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                content
                    .frame(maxWidth: 500)
                    .frame(maxWidth: .infinity)
                    .padding(Theme.Spacing.lg)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Add Friend")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task(id: uid) {
                friendService.startListening()
                await load()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading:
            ProgressView("Loading profile")
                .padding(.top, 40)
        case .loaded(let user):
            loadedContent(for: user)
        case .notFound:
            ContentUnavailableView(
                "This profile can't be found",
                systemImage: "person.crop.circle.badge.questionmark"
            )
        case .ownProfile:
            ContentUnavailableView(
                "That's your own profile",
                systemImage: "person.crop.circle",
                description: Text("Share your link or QR code so friends can add you.")
            )
        case .failed:
            ContentUnavailableView {
                Label("Couldn't load this profile", systemImage: "exclamationmark.triangle")
            } description: {
                Text("Check your connection and try again.")
            } actions: {
                Button("Try Again") { Task { await load() } }
            }
        }
    }

    private func loadedContent(for user: FirestoreUser) -> some View {
        VStack(spacing: Theme.Spacing.xl) {
            AvatarView(user: user, size: 96)
                .padding(.top, Theme.Spacing.sm)

            Text("Add \(user.shownName) (@\(user.username))?")
                .textStyle(.heading)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)

            action(for: user)

            FormErrorText(message: requestErrorMessage)
        }
    }

    @ViewBuilder
    private func action(for user: FirestoreUser) -> some View {
        switch friendService.relationship(withUID: uid) {
        case .none:
            Button {
                send(to: user)
            } label: {
                Text("Send friend request").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bloomPrimary)
        case .outgoingPending:
            Button {
            } label: {
                Text("Request sent").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bloomSecondary)
            .disabled(true)
        case .friends:
            Button {
            } label: {
                Text("Already friends").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bloomSecondary)
            .disabled(true)
        case .incomingPending:
            Button {
                accept()
            } label: {
                Text("Accept request").frame(maxWidth: .infinity)
            }
            .buttonStyle(.bloomPrimary)
        }
    }

    private func load() async {
        guard let myUID = Auth.auth().currentUser?.uid else {
            state = .failed
            return
        }
        guard uid != myUID else {
            state = .ownProfile
            return
        }

        state = .loading
        do {
            let snapshot = try await Firestore.firestore().collection("users").document(uid).getDocument()
            guard snapshot.exists else {
                state = .notFound
                return
            }
            state = .loaded(try snapshot.data(as: FirestoreUser.self))
        } catch {
            state = .failed
        }
    }

    private func send(to user: FirestoreUser) {
        requestErrorMessage = nil
        Task {
            do {
                try await friendService.sendFriendRequest(to: user)
            } catch {
                requestErrorMessage = error.localizedDescription
            }
        }
    }

    private func accept() {
        guard let incoming = friendService.incomingRequest(fromUID: uid) else { return }
        requestErrorMessage = nil
        Task {
            do {
                try await friendService.acceptFriendRequest(incoming)
            } catch {
                requestErrorMessage = error.localizedDescription
            }
        }
    }
}

#Preview {
    AddByLinkSheet(uid: "preview")
}
