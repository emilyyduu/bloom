import SwiftUI

// What a person asked to do about someone else's content or account.
enum ModerationRequest: Identifiable {
    case report(ReportTarget)
    case block(uid: String, name: String)

    var id: String {
        switch self {
        case .report(let target): return "report_\(target.id)"
        case .block(let uid, _): return "block_\(uid)"
        }
    }
}

extension View {
    // Presents the report sheet or the block confirmation for whatever
    // request is set, and clears it when done.
    func moderation(_ request: Binding<ModerationRequest?>) -> some View {
        modifier(ModerationModifier(request: request))
    }
}

private struct ModerationModifier: ViewModifier {
    @Binding var request: ModerationRequest?
    @State private var errorMessage: String?

    private var reportTarget: Binding<ReportTarget?> {
        Binding(
            get: { if case .report(let target) = request { return target } else { return nil } },
            set: { if $0 == nil { request = nil } }
        )
    }

    private var blockName: String? {
        if case .block(_, let name) = request { return name } else { return nil }
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: reportTarget) { target in
                ReportSheet(target: target)
            }
            .alert(
                "Block \(blockName ?? "this person")?",
                isPresented: Binding(get: { blockName != nil }, set: { if !$0 { request = nil } })
            ) {
                Button("Block", role: .destructive) { block() }
                Button("Cancel", role: .cancel) { request = nil }
            } message: {
                Text("You will stop being friends, they can\u{2019}t send you requests, and you won\u{2019}t see what they write. They are not told. You can unblock them in Settings, Privacy.")
            }
            .alert(
                "Couldn\u{2019}t block",
                isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })
            ) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func block() {
        guard case .block(let uid, _) = request else { return }
        request = nil
        Task {
            do {
                try await BlockService.shared.block(uid: uid)
            } catch {
                errorMessage = "Check your connection and try again."
            }
        }
    }
}

// The report form: a reason, optional details and Send. Reports go to the
// developer, and the person reported is not told who sent one.
struct ReportSheet: View {
    let target: ReportTarget

    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportReason = .inappropriate
    @State private var details = ""
    @State private var isSending = false
    @State private var isSent = false
    @State private var errorMessage: String?

    private var heading: String {
        switch target.kind {
        case .note: return "Report this note"
        case .comment: return "Report this comment"
        case .user: return "Report \(target.reportedName)"
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isSent {
                    ContentUnavailableView(
                        "Thank you",
                        systemImage: "checkmark.circle",
                        description: Text("Your report was sent. You can also block \(target.reportedName) from their profile.")
                    )
                } else {
                    form
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle(heading)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isSent ? "Done" : "Cancel") { dismiss() }
                }
                if !isSent {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Send") { send() }
                            .disabled(isSending)
                    }
                }
            }
        }
        .interactiveDismissDisabled(isSending)
    }

    private var form: some View {
        Form {
            Section {
                Picker("Reason", selection: $reason) {
                    ForEach(ReportReason.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.inline)
                .labelsHidden()
            } header: {
                SectionHeader("What is wrong?")
            }

            Section {
                TextField("Add details (optional)", text: $details, axis: .vertical)
                    .lineLimit(3...6)
                    .onChange(of: details) { _, new in
                        if new.count > 500 { details = String(new.prefix(500)) }
                    }
            } header: {
                SectionHeader("Details")
            } footer: {
                Text("Reports are read by the developer. The person is not told who reported them.")
            }

            if let errorMessage {
                Section { AuthErrorText(message: errorMessage) }
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func send() {
        isSending = true
        errorMessage = nil
        Task {
            do {
                try await ReportService.submit(target, reason: reason, details: details)
                isSent = true
            } catch {
                errorMessage = error.localizedDescription
            }
            isSending = false
        }
    }
}
