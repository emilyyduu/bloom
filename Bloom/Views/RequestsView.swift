import SwiftUI

// Friend requests in both directions: ones waiting on me to accept or
// decline, and ones I've sent that are still waiting on someone else.
struct RequestsView: View {
    @StateObject private var friendService = FriendService.shared

    private enum Segment: String, CaseIterable {
        case incoming = "Incoming"
        case outgoing = "Outgoing"
    }

    @State private var segment: Segment = .incoming
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Picker("Requests", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .padding()

            Group {
                switch segment {
                case .incoming:
                    incomingList
                case .outgoing:
                    outgoingList
                }
            }

            FormErrorText(message: errorMessage)
                .padding(.horizontal)
                .padding(.bottom, 8)
        }
        .navigationTitle("Requests")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var incomingList: some View {
        Group {
            if friendService.pendingIncoming.isEmpty {
                ContentUnavailableView(
                    "No Incoming Requests",
                    systemImage: "person.crop.circle.badge.questionmark",
                    description: Text("Requests other people send you will show up here.")
                )
            } else {
                List(friendService.pendingIncoming) { request in
                    IncomingRequestRow(
                        request: request,
                        name: friendService.pendingRequesterNames[request.fromUID] ?? "Someone",
                        onAccept: { accept(request) },
                        onDecline: { decline(request) }
                    )
                }
            }
        }
    }

    private var outgoingList: some View {
        Group {
            if friendService.pendingOutgoing.isEmpty {
                ContentUnavailableView(
                    "No Outgoing Requests",
                    systemImage: "paperplane",
                    description: Text("Requests you send will show up here until they're accepted.")
                )
            } else {
                List(friendService.pendingOutgoing) { request in
                    OutgoingRequestRow(
                        request: request,
                        name: friendService.pendingRecipientNames[request.toUID] ?? "Someone",
                        onCancel: { cancel(request) }
                    )
                }
            }
        }
    }

    private func accept(_ request: Friendship) {
        errorMessage = nil
        Task {
            do {
                try await friendService.acceptFriendRequest(request)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func decline(_ request: Friendship) {
        errorMessage = nil
        Task {
            do {
                try await friendService.declineRequest(request)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func cancel(_ request: Friendship) {
        errorMessage = nil
        Task {
            do {
                try await friendService.cancelRequest(request)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// How long ago a request was created, in "2 hours ago" form.
private func relativeTime(since date: Date) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.unitsStyle = .full
    return formatter.localizedString(for: date, relativeTo: Date())
}

private struct IncomingRequestRow: View {
    let request: Friendship
    let name: String
    let onAccept: () -> Void
    let onDecline: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(relativeTime(since: request.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Decline", role: .destructive) { onDecline() }
                .buttonStyle(.bordered)
            Button("Accept") { onAccept() }
                .buttonStyle(.borderedProminent)
        }
    }
}

private struct OutgoingRequestRow: View {
    let request: Friendship
    let name: String
    let onCancel: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                Text(relativeTime(since: request.createdAt))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("Pending")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Cancel", role: .destructive) { onCancel() }
                .buttonStyle(.bordered)
        }
    }
}

#Preview {
    NavigationStack {
        RequestsView()
    }
}
