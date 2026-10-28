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

    private var handle: AuthStateDidChangeListenerHandle?

    private init() {
        handle = Auth.auth().addStateDidChangeListener { [weak self] _, user in
            self?.isSignedIn = user != nil
        }
    }

    enum AuthServiceError: Error {
        case missingVerificationID
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

    // Email

    func signUpWithEmail(email: String, password: String) async throws {
        try await Auth.auth().createUser(withEmail: email, password: password)
    }

    func signInWithEmail(email: String, password: String) async throws {
        try await Auth.auth().signIn(withEmail: email, password: password)
    }

    func signOut() throws {
        try Auth.auth().signOut()
    }

    // User profile

    // Creates the small Firestore record, username and, for phone
    // sign-ups, the verified phone number, that makes an account
    // findable by someone else. Called once, immediately after sign-up
    // succeeds. The security rules only allow displayName, username,
    // usernameLower, createdAt and phoneNumber on this document, email
    // is never written here, and displayName, username and
    // usernameLower are always written together.
    // Merges rather than overwrites, so a record already holding a
    // phone number can't be clobbered by a later call without one.
    func createUserProfile(displayName: String, username: String, phoneNumber: String?) async throws {
        guard let uid = Auth.auth().currentUser?.uid else { return }

        let displayName = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let username = username.trimmingCharacters(in: .whitespacesAndNewlines)
        var data: [String: Any] = [
            "displayName": displayName,
            "username": username,
            "usernameLower": username.lowercased(),
            "createdAt": Date(),
        ]
        if let phoneNumber { data["phoneNumber"] = phoneNumber }

        try await Firestore.firestore().collection("users").document(uid).setData(data, merge: true)
    }
}
