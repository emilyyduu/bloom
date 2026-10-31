import Foundation
import FirebaseAuth
import FirebaseFirestore
import Combine

// Wraps Firebase Authentication for Bloom's two sign-up paths: a phone
// number verified by a one-time SMS code, or an email and password.
// Both end up as an ordinary FirebaseAuth user; the credential type used
// to create the account is the only difference.
@MainActor
final class AuthService: ObservableObject {
    static let shared = AuthService()

    // Drives BloomApp's decision between showing the auth flow or the
    // main app, updated automatically whenever Firebase's own sign-in
    // state changes.
    @Published var isSignedIn = false

    // The signed-in account's uid, nil when signed out. BloomApp keys the
    // signed-in UI and its per account SwiftData store on this.
    @Published private(set) var uid: String?

    // True while a phone log in is checking that the account has a profile.
    // Firebase signs the person in as soon as the code is accepted, so the
    // root view uses this to hold back the main app until the check ends.
    @Published private(set) var isCheckingLogin = false

    private var handle: AuthStateDidChangeListenerHandle?

    private init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            guard let self else { return }
            // Covers a sign out that didn't come from Settings (for
            // example a revoked session) or one account replacing another.
            if let previous = self.uid, previous != user?.uid {
                self.resetInMemoryAccountState()
            }
            self.uid = user?.uid
            self.isSignedIn = user != nil
            if user != nil { Task { await self.removeLegacyPhoneNumber() } }
        }
    }

    // Clears everything held in memory about the account that was
    // signed in, so the next account starts clean. Safe to call twice.
    // Local notes need no clearing here, each account has its own store.
    func resetInMemoryAccountState() {
        FriendService.shared.stopListening()
        CircleStore.shared.stopListening()
        BlockService.shared.stopListening()
        GardenService.shared.stopListening()
        FriendJournalService.shared.reset()
        MyAvatar.shared.reset()
        JournalCoverStore.shared.reset()
        NoteSyncService.shared.reset()
        LibrarySyncService.shared.reset()
        ProfileLinkCoordinator.shared.reset()
        ActivityStore.shared.stopListening()
        ActivityRouter.shared.reset()
        NotificationBadge.shared.clear()
        CommentCounts.shared.reset()
        ReactionCounts.shared.reset()
        Task { await UserProfileCache.shared.reset() }
        Task { await NotificationScheduler.shared.cancelAllReminders() }
    }

    enum AuthServiceError: Error {
        case missingVerificationID
        case cannotReauthenticate
    }

    // Phone
    // Sends a one-time SMS code and returns a verification ID used to
    // confirm it in PhoneVerificationView. Firebase handles the actual
    // SMS delivery and, behind the scenes, silent push or reCAPTCHA
    // verification that the request isn't automated, see the README for
    // the project setup this needs.
    func startPhoneVerification(phoneNumber: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil) { verificationID, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let verificationID {
                    continuation.resume(returning: verificationID)
                } else {
                    continuation.resume(throwing: AuthServiceError.missingVerificationID)
                }
            }
        }
    }

    func confirmPhoneCode(verificationID: String, code: String) async throws {
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        try await Auth.auth().signIn(with: credential)
    }

    enum LoginCheckError: LocalizedError {
        case noAccount
        case couldNotCheck

        var errorDescription: String? {
            switch self {
            case .noAccount:
                return "There's no Bloom account for this number. Go back and sign up."
            case .couldNotCheck:
                return "Couldn't check your account. Check your connection and try again."
            }
        }
    }

    // Confirms a code for a log in (not a sign up). Firebase creates a user
    // for any verified number, so this then checks that users/{uid} exists.
    // A number that never signed up has its new Auth user deleted again, and
    // if the check can't be made the person is just signed out.
    func confirmPhoneLogin(verificationID: String, code: String) async throws {
        isCheckingLogin = true
        defer { isCheckingLogin = false }

        try await confirmPhoneCode(verificationID: verificationID, code: code)
        guard let user = Auth.auth().currentUser else { throw LoginCheckError.couldNotCheck }

        let snapshot: DocumentSnapshot
        do {
            snapshot = try await Firestore.firestore().collection("users").document(user.uid)
                .getDocument(source: .server)
        } catch {
            try? Auth.auth().signOut()
            throw LoginCheckError.couldNotCheck
        }

        if !snapshot.exists {
            try? await user.delete()
            try? Auth.auth().signOut()
            throw LoginCheckError.noAccount
        }
    }

    // Email

    func signUpWithEmail(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signInWithEmail(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    // Sends Firebase's password reset email. An address with no account is
    // treated as success, so this can't be used to find out who has one.
    func sendPasswordReset(email: String) async throws {
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await Auth.auth().sendPasswordReset(withEmail: email)
        } catch let error as NSError where error.code == AuthErrorCode.userNotFound.rawValue {
            return
        }
    }

    // Signing in again, which Firebase requires shortly before it will
    // delete an account. How to do it depends on how the account signs in.
    enum ReauthMethod {
        case password
        case phone
    }

    var reauthMethod: ReauthMethod? {
        let providers = Auth.auth().currentUser?.providerData.map(\.providerID) ?? []
        if providers.contains("password") { return .password }
        if providers.contains("phone") { return .phone }
        return nil
    }

    func reauthenticate(password: String) async throws {
        guard let user = Auth.auth().currentUser, let email = user.email else {
            throw AuthServiceError.cannotReauthenticate
        }
        let credential = EmailAuthProvider.credential(withEmail: email, password: password)
        try await user.reauthenticate(with: credential)
    }

    // Texts a code to the number on the account and returns the id to
    // confirm it with.
    func startPhoneReauthentication() async throws -> String {
        guard let number = Auth.auth().currentUser?.phoneNumber else {
            throw AuthServiceError.cannotReauthenticate
        }
        return try await startPhoneVerification(phoneNumber: number)
    }

    func reauthenticate(verificationID: String, code: String) async throws {
        guard let user = Auth.auth().currentUser else { throw AuthServiceError.cannotReauthenticate }
        let credential = PhoneAuthProvider.provider().credential(
            withVerificationID: verificationID,
            verificationCode: code
        )
        try await user.reauthenticate(with: credential)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // User profile

    // Creates the small Firestore record, username and display name, that
    // makes an account findable by someone else. Called once, immediately
    // after sign-up succeeds. The security rules only allow displayName,
    // username, usernameLower and createdAt on this document (plus the
    // avatar flags). Email and phone number are never written here, they
    // stay in Firebase Authentication. displayName, username and
    // usernameLower are always written together.
    func createUserProfile(displayName: String, username: String) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let data: [String: Any] = [
            "displayName": displayName,
            "username": username,
            "usernameLower": username.lowercased(),
            "createdAt": Date(),
        ]

        try await Firestore.firestore().collection("users").document(uid).setData(data, merge: true)
    }

    // Runs right after an account is created. Saves the profile, once more
    // if the first try fails. If it still can't be saved the new account is
    // deleted again, so nobody is left signed in without a profile that
    // friends could never find, and the person can simply try again.
    func completeSignUp(displayName: String, username: String) async throws {
        do {
            do {
                try await createUserProfile(displayName: displayName, username: username)
            } catch {
                try await createUserProfile(displayName: displayName, username: username)
            }
        } catch {
            try? await Auth.auth().currentUser?.delete()
            try? Auth.auth().signOut()
            throw error
        }
    }

    // Earlier builds stored the verified phone number on the profile so
    // contacts could be matched. Nothing reads it any more, so it is
    // removed from any profile that still has it.
    func removeLegacyPhoneNumber() async {
        guard let uid = Auth.auth().currentUser?.uid else { return }
        let reference = Firestore.firestore().collection("users").document(uid)
        guard let snapshot = try? await reference.getDocument(),
              snapshot.get("phoneNumber") != nil else { return }
        try? await reference.updateData(["phoneNumber": FieldValue.delete()])
    }
}
