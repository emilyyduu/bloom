import SwiftUI

// A multi-select list of friends, shared by the new circle sheet and Add
// people. At the limit the rows that aren't selected disable and say why.
struct FriendPickerList: View {
    let friends: [FirestoreUser]
    @Binding var selected: Set<String>
    // How many people can be selected in total.
    let limit: Int

    var body: some View {
        ForEach(friends) { friend in
            if let id = friend.id {
                let isSelected = selected.contains(id)
                let isBlocked = !isSelected && !CircleLimits.canAdd(current: selected.count, limit: limit)

                Button {
                    if isSelected { selected.remove(id) } else { selected.insert(id) }
                } label: {
                    HStack(spacing: 12) {
                        AvatarView(user: friend, size: 40)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(friend.shownName)
                                .foregroundStyle(.primary)
                            Text("@\(friend.username)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            if isBlocked {
                                Text("A circle can have up to \(CircleLimits.maxMembers) people")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer(minLength: 8)
                        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                            .font(.title3)
                            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isBlocked)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(isSelected ? .isSelected : [])
                .accessibilityHint(isBlocked ? "A circle can have up to \(CircleLimits.maxMembers) people" : "")
            }
        }
    }
}

// Create a circle: a name and the friends in it.
struct NewCircleSheet: View {
    // Friends ticked when the sheet opens, from "New circle" on a profile.
    var preselected: [String] = []
    var onCreated: ((FriendCircle) -> Void)?

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var circleStore = CircleStore.shared
    @ObservedObject private var friendService = FriendService.shared

    @State private var name = ""
    @State private var selected: Set<String> = []
    @State private var errorMessage: String?
    @State private var isSaving = false
    @FocusState private var isNameFocused: Bool

    private var friends: [FirestoreUser] {
        friendService.friends
            .sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
    }

    private var nameProblem: CircleNameError? {
        CircleLimits.nameError(name, existingNames: circleStore.circles.map(\.name))
    }

    private var canCreate: Bool {
        !CircleLimits.trimmed(name).isEmpty && nameProblem == nil && !isSaving
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    TextField("Circle name", text: $name)
                        .focused($isNameFocused)
                        .submitLabel(.done)
                        .frame(minHeight: 44)
                    // Empty isn't an error until they try, only a disabled button.
                    if !CircleLimits.trimmed(name).isEmpty, let problem = nameProblem {
                        Label(problem.message, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                } footer: {
                    Text("Only you can see your circles.")
                }

                Section {
                    if friends.isEmpty {
                        Text("Add friends first, then you can put them in a circle.")
                            .foregroundStyle(.secondary)
                    }
                    FriendPickerList(friends: friends, selected: $selected, limit: CircleLimits.maxMembers)
                } header: {
                    Text("\(selected.count) of \(CircleLimits.maxMembers) selected")
                        .accessibilityAddTraits(.isHeader)
                }

                if let errorMessage {
                    Section { FormErrorText(message: errorMessage) }
                }
            }
            .navigationTitle("New circle")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") { create() }
                        .disabled(!canCreate)
                }
            }
            .onAppear {
                let ids = Set(friends.compactMap(\.id))
                selected = Set(preselected).intersection(ids)
                isNameFocused = true
            }
        }
    }

    private func create() {
        errorMessage = nil
        isSaving = true
        Task {
            do {
                let circle = try await circleStore.create(name: name, memberUIDs: Array(selected))
                isSaving = false
                dismiss()
                onCreated?(circle)
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}

// Add people to a circle, listing only friends who aren't in it yet.
struct AddPeopleSheet: View {
    let circle: FriendCircle

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var circleStore = CircleStore.shared
    @ObservedObject private var friendService = FriendService.shared

    @State private var selected: Set<String> = []
    @State private var errorMessage: String?
    @State private var isSaving = false

    private var currentMembers: Set<String> { Set(circleStore.memberUIDs(of: circle)) }

    private var candidates: [FirestoreUser] {
        friendService.friends
            .filter { friend in friend.id.map { !currentMembers.contains($0) } ?? false }
            .sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
    }

    private var remaining: Int { CircleLimits.remainingSlots(current: currentMembers.count) }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if candidates.isEmpty {
                        Text("Everyone you are friends with is already in this circle.")
                            .foregroundStyle(.secondary)
                    }
                    FriendPickerList(friends: candidates, selected: $selected, limit: remaining)
                } header: {
                    Text("\(selected.count) selected, \(remaining) \(remaining == 1 ? "spot" : "spots") left")
                        .accessibilityAddTraits(.isHeader)
                }

                if let errorMessage {
                    Section { FormErrorText(message: errorMessage) }
                }
            }
            .navigationTitle("Add people")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { add() }
                        .disabled(selected.isEmpty || isSaving)
                }
            }
        }
    }

    private func add() {
        errorMessage = nil
        isSaving = true
        Task {
            do {
                try await circleStore.add(Array(selected), to: circle)
                isSaving = false
                dismiss()
            } catch {
                isSaving = false
                errorMessage = error.localizedDescription
            }
        }
    }
}
