import Foundation
import Testing
@testable import Bloom

@MainActor
@Suite("Comment and reply grouping")
struct CommentThreadTests {
    private func comment(_ id: String, minute: Int, replyTo parent: String? = nil) -> NoteComment {
        NoteComment(
            id: id, authorUID: "author-\(id)", text: "text \(id)",
            createdAt: TestClock.date(2026, 10, 30, 9, minute),
            replyToUID: parent.map { "author-\($0)" }, replyToCommentId: parent
        )
    }

    @Test("No comments gives no threads")
    func empty() {
        #expect(CommentThread.threads(from: []).isEmpty)
    }

    @Test("Top level comments come out oldest first, whatever order they arrive in")
    func topLevelOrder() {
        let threads = CommentThread.threads(from: [comment("c", minute: 30), comment("a", minute: 10), comment("b", minute: 20)])
        #expect(threads.map(\.top.id) == ["a", "b", "c"])
        #expect(threads.allSatisfy { $0.replies.isEmpty && !$0.parentDeleted })
    }

    @Test("Replies sit under their parent, oldest first")
    func repliesUnderParent() {
        let threads = CommentThread.threads(from: [
            comment("r2", minute: 40, replyTo: "a"),
            comment("a", minute: 10),
            comment("b", minute: 20),
            comment("r1", minute: 30, replyTo: "a"),
            comment("rb", minute: 50, replyTo: "b"),
        ])
        #expect(threads.map(\.top.id) == ["a", "b"])
        #expect(threads[0].replies.map(\.id) == ["r1", "r2"])
        #expect(threads[1].replies.map(\.id) == ["rb"])
        #expect(threads.allSatisfy { !$0.parentDeleted })
    }

    @Test("A reply whose parent was deleted becomes a normal comment, marked as such")
    func orphanReply() throws {
        let threads = CommentThread.threads(from: [comment("a", minute: 10), comment("orphan", minute: 20, replyTo: "gone")])
        #expect(threads.map(\.top.id) == ["a", "orphan"])
        let orphan = try #require(threads.last)
        #expect(orphan.parentDeleted)
        #expect(orphan.replies.isEmpty)
        #expect(orphan.top.isReply)
        #expect(!threads[0].parentDeleted)
    }

    @Test("Replies to an orphan stay under the orphan")
    func repliesToOrphan() {
        let threads = CommentThread.threads(from: [
            comment("orphan", minute: 20, replyTo: "gone"),
            comment("child", minute: 30, replyTo: "orphan"),
        ])
        #expect(threads.count == 1)
        #expect(threads[0].top.id == "orphan")
        #expect(threads[0].replies.map(\.id) == ["child"])
    }

    @Test("A reply to a reply is flattened under the top level comment")
    func replyToReply() {
        let threads = CommentThread.threads(from: [
            comment("a", minute: 10),
            comment("r1", minute: 20, replyTo: "a"),
            comment("r2", minute: 30, replyTo: "r1"),
        ])
        #expect(threads.count == 1)
        #expect(threads[0].replies.map(\.id) == ["r1", "r2"])
    }

    @Test("A comment that replies to itself stands alone instead of looping")
    func selfReply() {
        let threads = CommentThread.threads(from: [comment("loop", minute: 10, replyTo: "loop")])
        #expect(threads.map(\.top.id) == ["loop"])
        #expect(threads[0].replies.isEmpty)
    }

    @Test("Comments made in the same minute are ordered by id so the result is stable")
    func tieBreak() {
        let threads = CommentThread.threads(from: [comment("b", minute: 10), comment("a", minute: 10)])
        #expect(threads.map(\.top.id) == ["a", "b"])
    }

    @Test("The comment length limit is 500")
    func maxLength() {
        #expect(NoteComment.maxLength == 500)
    }
}
