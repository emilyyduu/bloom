import SwiftUI

// One circle: its people, with Add people, Rename and Delete circle.
struct CircleDetailView: View {
    let circleID: String

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var circleStore = CircleStore.shared
    @ObservedObject private var friendService = FriendService.shared

    @State private var isShowingAddPeople = false
    @State private var isShowingRename = false
    @State private var isShowingDelete = false
    @State private var errorMessage: String?

    private var circle: FriendCircle? { circleStore.circle(id: circleID) }

    var body: some View {
        Group {
            if let circle {
                content(for: circle)
            } else {
                // Deleted, here or on another device.
                Color.clear
            }
        }
        .navigationTitle(circle?.name ?? "Circle")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: circle == nil) { _, isGone in
            if isGone, circleStore.isReady { dismiss() }
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

    @ViewBuilder
    private func content(for circle: FriendCircle) -> some View {
        let friends = friendService.friends
        let members = circleStore.members(of: circle, among: friends)

        List {
            Section {
                ForEach(members) { member in
                    NavigationLink {
                        FriendProfileView(friend: member)
                    } label: {
                        HStack(spacing: Theme.Spacing.md) {
                            AvatarView(user: member, size: 40)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(member.shownName)
                                Text("@\(member.username)")
                                    .textStyle(.callout)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                            }
                        }
                        .frame(minHeight: 44)
                    }
                    .swipeActions(edge: .trailing) {
                        Button("Remove", role: .destructive) { remove(member, from: circle) }
                    }
                    .accessibilityAction(named: "Remove from circle") { remove(member, from: circle) }
                }
            } header: {
                Text("\(members.count) of \(CircleLimits.maxMembers)")
                    .accessibilityAddTraits(.isHeader)
            }

            Section {
                Button {
                    isShowingAddPeople = true
                } label: {
                    Label("Add people", systemImage: "person.badge.plus")
                        .frame(minHeight: 44)
                }
                .disabled(!CircleLimits.canAdd(current: members.count))

                Button {
                    isShowingRename = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                        .frame(minHeight: 44)
                }

                Button(role: .destructive) {
                    isShowingDelete = true
                } label: {
                    Label("Delete circle", systemImage: "trash")
                        .frame(minHeight: 44)
                }
            } footer: {
                if !CircleLimits.canAdd(current: members.count) {
                    Text("A circle can have up to \(CircleLimits.maxMembers) people")
                } else {
                    Text("Only you can see this circle.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.Colors.background)
        .overlay {
            if members.isEmpty {
                EmptyStateView(
                    title: "No one in this circle yet",
                    message: "Choose friends to add to it.",
                    systemImage: "person.2"
                ) {
                    Button("Add people") { isShowingAddPeople = true }
                        .buttonStyle(.bloomPrimary)
                }
                // Sits above the list's action rows without covering them.
                .padding(.bottom, 220)
            }
        }
        .sheet(isPresented: $isShowingAddPeople) {
            AddPeopleSheet(circle: circle)
        }
        .sheet(isPresented: $isShowingRename) {
            RenameCircleSheet(circle: circle)
        }
        .confirmationDialog(
            "Delete the circle \(circle.name)? Your friends stay friends.",
            isPresented: $isShowingDelete,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) { delete(circle) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func remove(_ member: FirestoreUser, from circle: FriendCircle) {
        guard let id = member.id else { return }
        Task {
            do {
                try await circleStore.remove(id, from: circle)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func delete(_ circle: FriendCircle) {
        Task {
            do {
                try await circleStore.delete(circle)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
