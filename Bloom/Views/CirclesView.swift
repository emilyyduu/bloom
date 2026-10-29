import SwiftUI

// Profile > Circles: All friends first, then each circle. Circles are
// private to me, the people in them aren't told and can't see them.
struct CirclesView: View {
    @ObservedObject private var circleStore = CircleStore.shared
    @ObservedObject private var friendService = FriendService.shared

    @State private var isShowingNewCircle = false
    @State private var isShowingCircleLimit = false
    @State private var circleToRename: FriendCircle?
    @State private var circleToDelete: FriendCircle?
    @State private var errorMessage: String?

    private var friends: [FirestoreUser] { circleStore.allFriends(real: friendService.friends) }

    var body: some View {
        List {
            Section {
                NavigationLink {
                    FriendsView()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "person.2")
                            .frame(width: 28)
                            .accessibilityHidden(true)
                        Text("All friends (\(friends.count))")
                    }
                    .frame(minHeight: 44)
                }
            }

            Section {
                ForEach(circleStore.circles) { circle in
                    NavigationLink {
                        CircleDetailView(circleID: circle.id)
                    } label: {
                        CircleRow(circle: circle, friends: friends)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button("Delete", role: .destructive) { circleToDelete = circle }
                        Button("Rename") { circleToRename = circle }
                            .tint(.accentColor)
                    }
                    .accessibilityAction(named: "Rename") { circleToRename = circle }
                    .accessibilityAction(named: "Delete") { circleToDelete = circle }
                }
            } header: {
                SectionHeader("Circles")
            } footer: {
                Text("Only you can see your circles.")
            }

            if let message = circleStore.errorMessage {
                Section {
                    FormErrorText(message: message)
                    if circleStore.state == .failed {
                        Button("Retry") { circleStore.retry() }
                            .frame(minHeight: 44)
                    }
                }
            }
        }
        .navigationTitle("Circles")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    if CircleLimits.canAdd(current: circleStore.circles.count, limit: CircleLimits.maxCircles) {
                        isShowingNewCircle = true
                    } else {
                        isShowingCircleLimit = true
                    }
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("New circle")
            }
        }
        .sheet(isPresented: $isShowingNewCircle) {
            NewCircleSheet()
        }
        .sheet(item: $circleToRename) { circle in
            RenameCircleSheet(circle: circle)
        }
        .alert("You can have up to \(CircleLimits.maxCircles) circles", isPresented: $isShowingCircleLimit) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Delete one to make a new one.")
        }
        .confirmationDialog(
            "Delete the circle \(circleToDelete?.name ?? "")? Your friends stay friends.",
            isPresented: Binding(get: { circleToDelete != nil }, set: { if !$0 { circleToDelete = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let circle = circleToDelete { delete(circle) }
                circleToDelete = nil
            }
            Button("Cancel", role: .cancel) { circleToDelete = nil }
        }
        .alert("Couldn\u{2019}t change the circle", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(errorMessage ?? "")
        }
        .task {
            friendService.startListening()
            circleStore.startListening()
        }
    }

    private func delete(_ circle: FriendCircle) {
        Task {
            do {
                try await circleStore.delete(circle)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

// A circle's name, up to four member avatars and "3 of 10".
private struct CircleRow: View {
    let circle: FriendCircle
    let friends: [FirestoreUser]

    @ObservedObject private var circleStore = CircleStore.shared

    private var members: [FirestoreUser] { circleStore.members(of: circle, among: friends) }
    private var count: Int { circleStore.memberUIDs(of: circle).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(circle.name)
                .font(.headline)
            HStack(spacing: 8) {
                HStack(spacing: -10) {
                    ForEach(members.prefix(4)) { member in
                        AvatarView(user: member, size: 28, relativeTo: .caption)
                            .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    }
                }
                .accessibilityHidden(true)
                Text("\(count) of \(CircleLimits.maxMembers)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .frame(minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(circle.name), \(count) of \(CircleLimits.maxMembers) people")
    }
}

// Rename with the same inline name check as creating.
struct RenameCircleSheet: View {
    let circle: FriendCircle

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var circleStore = CircleStore.shared

    @State private var name: String
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(circle: FriendCircle) {
        self.circle = circle
        _name = State(initialValue: circle.name)
    }

    private var problem: CircleNameError? {
        CircleLimits.nameError(name, existingNames: circleStore.circles.filter { $0.id != circle.id }.map(\.name))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Circle name", text: $name)
                        .frame(minHeight: 44)
                    if !CircleLimits.trimmed(name).isEmpty, let problem {
                        Label(problem.message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    FormErrorText(message: errorMessage)
                }
            }
            .navigationTitle("Rename circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(problem != nil || isSaving)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func save() {
        isSaving = true
        Task {
            do {
                try await circleStore.rename(circle, to: name)
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
