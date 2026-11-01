import Foundation
import FirebaseAuth
import FirebaseFirestore

enum ReportReason: String, CaseIterable, Identifiable {
    case spam
    case harassment
    case inappropriate
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .spam: return "Spam"
        case .harassment: return "Harassment or bullying"
        case .inappropriate: return "Inappropriate content"
        case .other: return "Something else"
        }
    }
}

// What is being reported: a note, a comment on a note, or a person.
struct ReportTarget: Identifiable, Equatable {
    enum Kind: String {
        case note
        case comment
        case user
    }

    let kind: Kind
    let reportedUID: String
    // Who to call them in the sheet's title.
    let reportedName: String
    var noteOwnerUID: String?
    var noteID: String?
    var commentID: String?
    // What the reporter saw, cut to 500 characters. It lets a report be
    // understood after the content has been deleted.
    var preview: String?

    var id: String { "\(kind.rawValue)_\(commentID ?? noteID ?? reportedUID)" }

    static func note(ownerUID: String, ownerName: String, noteID: String, text: String) -> ReportTarget {
        ReportTarget(kind: .note, reportedUID: ownerUID, reportedName: ownerName, noteOwnerUID: ownerUID, noteID: noteID, preview: text)
    }

    static func comment(authorUID: String, authorName: String, noteOwnerUID: String, noteID: String, commentID: String, text: String) -> ReportTarget {
        ReportTarget(kind: .comment, reportedUID: authorUID, reportedName: authorName, noteOwnerUID: noteOwnerUID, noteID: noteID, commentID: commentID, preview: text)
    }

    static func user(uid: String, name: String) -> ReportTarget {
        ReportTarget(kind: .user, reportedUID: uid, reportedName: name)
    }
}

enum ReportError: LocalizedError {
    case notSignedIn
    case alreadyReported
    case failed

    var errorDescription: String? {
        switch self {
        case .notSignedIn: return "You are not signed in."
        case .alreadyReported: return "You have already reported this."
        case .failed: return "Couldn\u{2019}t send the report. Check your connection and try again."
        }
    }
}

// Files a report at reports/{reporterUID}_{kind}_{targetId}. The id makes a
// second report of the same thing by the same person impossible. Nobody can
// read reports from the app: they are reviewed in the Firebase console, see
// docs/moderation.md.
@MainActor
enum ReportService {
    static func submit(_ target: ReportTarget, reason: ReportReason, details: String) async throws {
        guard let me = Auth.auth().currentUser?.uid else { throw ReportError.notSignedIn }

        var data: [String: Any] = [
            "reporterUID": me,
            "reportedUID": target.reportedUID,
            "kind": target.kind.rawValue,
            "reason": reason.rawValue,
            "createdAt": Timestamp(date: Date()),
        ]
        let trimmedDetails = details.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedDetails.isEmpty { data["details"] = String(trimmedDetails.prefix(500)) }
        if let noteOwnerUID = target.noteOwnerUID { data["noteOwnerUID"] = noteOwnerUID }
        if let noteID = target.noteID { data["noteId"] = noteID }
        if let commentID = target.commentID { data["commentId"] = commentID }
        if let preview = target.preview, !preview.isEmpty { data["contentPreview"] = String(preview.prefix(500)) }

        let targetKey: String
        switch target.kind {
        case .user: targetKey = target.reportedUID
        case .note: targetKey = target.noteID ?? ""
        case .comment: targetKey = target.commentID ?? ""
        }

        do {
            try await Firestore.firestore().collection("reports")
                .document("\(me)_\(target.kind.rawValue)_\(targetKey)")
                .setData(data)
        } catch {
            let nsError = error as NSError
            if nsError.domain == FirestoreErrorDomain, nsError.code == FirestoreErrorCode.permissionDenied.rawValue {
                // The rules refuse a second report of the same thing.
                throw ReportError.alreadyReported
            }
            throw ReportError.failed
        }
    }
}
