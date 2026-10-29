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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(spacing: 0) {
            segmentPicker
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

    // The segmented style truncates "Incoming"/"Outgoing" at
    // accessibility sizes, so it becomes a menu instead; the binding is
    // unchanged either way, so the current choice is never lost.
    @ViewBuilder
    private var segmentPicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker("Requests", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.menu)
        } else {
            Picker("Requests", selection: $segment) {
                ForEach(Segment.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
        }
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
                        name: friendService.pendingRequesterProfiles[request.fromUID]?.shownName ?? "Someone",
                        username: friendService.pendingRequesterProfiles[request.fromUID]?.username,
                        profile: friendService.pendingRequesterProfiles[request.fromUID],
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
                        name: friendService.pendingRecipientProfiles[request.toUID]?.shownName ?? "Someone",
                        username: friendService.pendingRecipientProfiles[request.toUID]?.username,
                        profile: friendService.pendingRecipientProfiles[request.toUID],
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

// At accessibility sizes the trailing buttons move below the name and
// timestamp instead of squeezing them into a shrinking leading column.
// Shared by both row types below, and reused by NotificationsView for
// the bell's incoming-requests section.
func rowLayout(_ dynamicTypeSize: DynamicTypeSize) -> AnyLayout {
    dynamicTypeSize.isAccessibilitySize
        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
        : AnyLayout(HStackLayout())
}

// The avatar beside a request row. The profile can still be loading,
// in which case it shows initials until it arrives.
private struct RequestAvatar: View {
    let profile: FirestoreUser?
    let name: String

    var body: some View {
        Group {
            if let profile {
                AvatarView(user: profile, size: 40)
            } else {
                AvatarView(uid: nil, name: name, hasAvatar: false, avatarUpdatedAt: nil, size: 40)
            }
        }
        .accessibilityHidden(true)
    }
}

// Reused by NotificationsView so the bell's incoming requests look and
// behave exactly like the ones in Friends > Requests.
struct IncomingRequestRow: View {
    let request: Friendship
    let name: String
    let username: String?
    let profile: FirestoreUser?
    let onAccept: () -> Void
    let onDecline: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = rowLayout(dynamicTypeSize)
        layout {
            HStack(spacing: 12) {
                RequestAvatar(profile: profile, name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    if let username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(relativeTime(since: request.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }

            HStack {
                Button("Decline", role: .destructive) { onDecline() }
                    .buttonStyle(.bordered)
                Button("Accept") { onAccept() }
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

private struct OutgoingRequestRow: View {
    let request: Friendship
    let name: String
    let username: String?
    let profile: FirestoreUser?
    let onCancel: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        let layout = rowLayout(dynamicTypeSize)
        layout {
            HStack(spacing: 12) {
                RequestAvatar(profile: profile, name: name)
                VStack(alignment: .leading, spacing: 2) {
                    Text(name)
                    if let username {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    Text(relativeTime(since: request.createdAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }

            HStack {
                Text("Pending")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Button("Cancel", role: .destructive) { onCancel() }
                    .buttonStyle(.bordered)
            }
        }
    }
}

#Preview("Large") {
    NavigationStack {
        RequestsView()
    }
    .environment(\.dynamicTypeSize, .large)
}

#Preview("XXX Large") {
    NavigationStack {
        RequestsView()
    }
    .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Accessibility 5") {
    NavigationStack {
        RequestsView()
    }
    .environment(\.dynamicTypeSize, .accessibility5)
}
