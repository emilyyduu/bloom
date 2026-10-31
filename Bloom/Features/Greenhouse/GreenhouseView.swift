import SwiftUI

// The Greenhouse tab. The garden is a RealityKit scene (GardenRealityView):
// a small, non-interactive preview sits in the card below, and tapping
// it opens a full screen interactive version.
struct GreenhouseView: View {
    // Where the Greenhouse can push to.
    private enum Route: Hashable, Identifiable {
        case circles
        case circle(String)

        var id: String {
            switch self {
            case .circles: return "circles"
            case .circle(let id): return "circle-\(id)"
            }
        }
    }

    // What decides who is in the garden, so the listeners are only touched
    // when the people really change.
    private struct GardenKey: Equatable {
        let uids: [String]
        let isReady: Bool
    }

    // All friends shows this many, by name. Circles are how to choose.
    private static let allFriendsLimit = CircleLimits.maxMembers

    @StateObject private var gardenService = GardenService.shared
    @StateObject private var circleStore = CircleStore.shared
    @StateObject private var friendService = FriendService.shared
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isShowingFullScreenGarden = false
    @State private var route: Route?

    // In landscape on iPhone (compact height) the garden card and the
    // streaks list sit side by side instead of one on top of the
    // other, but both still scroll together in the one ScrollView.
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var panesLayout: AnyLayout {
        isCompactHeight
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
    }

    // MARK: Selection

    private var allFriends: [FirestoreUser] {
        friendService.friends
            .sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
    }

    private var selectedCircle: FriendCircle? { circleStore.gardenCircle }
    private var selectionName: String { selectedCircle?.name ?? "All friends" }

    // The friends in the garden: the circle's members, or the first 10 by name.
    private var shownFriends: [FirestoreUser] {
        if let selectedCircle {
            return circleStore.members(of: selectedCircle, among: allFriends)
                .sorted { $0.shownName.localizedCaseInsensitiveCompare($1.shownName) == .orderedAscending }
        }
        return Array(allFriends.prefix(Self.allFriendsLimit))
    }

    private var gardenKey: GardenKey {
        GardenKey(uids: shownFriends.compactMap(\.id), isReady: circleStore.isReady)
    }

    private var plants: [GardenPlant] { gardenService.plants }

    // Me first, then everyone else ordered by streak, highest first.
    // "No data" sorts last, below a 0 day wilted or withered streak.
    private var sortedPlants: [GardenPlant] {
        guard let me = plants.first else { return [] }
        let others = plants.dropFirst().sorted { displayStreak(for: $0) > displayStreak(for: $1) }
        return [me] + others
    }

    private var hasNoFriends: Bool { allFriends.isEmpty }
    private var isSelectedCircleEmpty: Bool { selectedCircle != nil && shownFriends.isEmpty }

    private func displayStreak(for plant: GardenPlant) -> Int {
        switch plant.plantState {
        case .blooming: return plant.currentStreak
        case .wilting, .dead: return 0
        case nil: return -1
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScreenHeader("Greenhouse")

                ScrollView {
                    panesLayout {
                        gardenPane
                        streaksPane
                    }
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Greenhouse")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                FriendService.shared.startListening()
                circleStore.startListening()
            }
            // Adds listeners for people who joined the selection and removes
            // them for people who left, the scene and camera stay as they are.
            .task(id: gardenKey) {
                guard circleStore.isReady else { return }
                gardenService.setPeople(friends: shownFriends)
            }
            .fullScreenCover(isPresented: $isShowingFullScreenGarden) {
                FullScreenGardenView(plants: plants, selectionName: selectionName)
            }
            .navigationDestination(item: $route) { route in
                switch route {
                case .circles: CirclesView()
                case .circle(let id): CircleDetailView(circleID: id)
                }
            }
        }
    }

    private var gardenPane: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 10 : Theme.Spacing.lg) {
            gardenSwitcher
            gardenCard
        }
        .padding(isCompactHeight ? 10 : Theme.Spacing.lg)
        .frame(maxWidth: isCompactHeight ? 340 : .infinity)
    }

    private var streaksPane: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 10 : Theme.Spacing.lg) {
            Text("VIEW STREAKS")
                .textStyle(.caption)
                .fontWeight(.semibold)
                .tracking(1.5)
                .foregroundStyle(Theme.Colors.textSecondary)

            streaksCard

            if let selectedCircle, isSelectedCircleEmpty {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Add people to \(selectedCircle.name)")
                        .textStyle(.callout)
                        .foregroundStyle(Theme.Colors.textSecondary)
                    Button("Add people") { route = .circle(selectedCircle.id) }
                        .buttonStyle(.bloomPrimary)
                }
            } else if hasNoFriends {
                Text("Add friends from Profile to grow your shared garden.")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            } else if selectedCircle == nil, allFriends.count > Self.allFriendsLimit {
                Text("Showing \(Self.allFriendsLimit) of \(allFriends.count) friends. Use circles to choose who appears.")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .padding(isCompactHeight ? 10 : Theme.Spacing.lg)
        .frame(maxWidth: .infinity)
    }

    // The current choice with a chevron: All friends, each circle, then
    // Manage circles. The saved circle is per account.
    private var gardenSwitcher: some View {
        Menu {
            Picker("Garden", selection: Binding<String?>(
                get: { selectedCircle?.id },
                set: { circleStore.selectGardenCircle($0) }
            )) {
                Text("All friends").tag(String?.none)
                ForEach(circleStore.circles) { circle in
                    Text(circle.name).tag(Optional(circle.id))
                }
            }
            Divider()
            Button("Manage circles") { route = .circles }
        } label: {
            HStack(spacing: 6) {
                Text("Garden: \(selectionName)")
                    .lineLimit(2)
                Image(systemName: "chevron.down")
                    .textStyle(.caption)
                    .accessibilityHidden(true)
            }
            .textStyle(.callout)
            .fontWeight(.medium)
            .foregroundStyle(Theme.Colors.textPrimary)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, 6)
            .frame(minHeight: 44)
            .background(Theme.Colors.surfaceMuted, in: Capsule())
        }
        .accessibilityLabel("Garden: \(selectionName)")
        .accessibilityHint("Choose All friends or a circle")
    }

    // The real RealityKit garden, shown small and non-interactive
    // here so the page still scrolls when a finger starts on the
    // card. Tapping it opens the full screen interactive version.
    private var gardenCard: some View {
        RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous)
            .fill(Theme.Palette.greenTint)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: isCompactHeight ? 260 : .infinity)
            .overlay {
                GardenRealityView(plants: plants, selectionName: selectionName)
                    .padding(Theme.Spacing.sm)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(Theme.Spacing.sm)
                    .background(.thinMaterial, in: Circle())
                    .padding(10)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.large, style: .continuous))
            .onTapGesture {
                isShowingFullScreenGarden = true
            }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Double tap to view full screen garden.")
    }

    private var streaksCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(sortedPlants.enumerated()), id: \.element.id) { index, plant in
                GardenStreakRow(plant: plant)
                if index < sortedPlants.count - 1 {
                    Divider().padding(.leading, 72)
                }
            }
        }
        .padding(.vertical, Theme.Spacing.xs)
        .background(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).fill(Theme.Colors.surfaceMuted))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous).strokeBorder(Theme.Colors.separator, lineWidth: 1))
    }
}

private struct GardenStreakRow: View {
    let plant: GardenPlant

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ObservedObject private var myAvatar = MyAvatar.shared

    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var statusWord: String {
        switch plant.plantState {
        case .blooming: return "Blooming"
        case .wilting: return "Wilting"
        case .dead: return "Withered"
        case nil: return "No posts yet"
        }
    }

    private var iconName: String {
        plant.plantState == nil ? "leaf" : "leaf.fill"
    }

    private var iconColor: Color {
        switch plant.plantState {
        case .blooming: return Theme.Colors.blooming
        case .wilting: return Theme.Colors.wilting
        case .dead: return Theme.Colors.dead
        case nil: return Theme.Colors.textSecondary
        }
    }

    private var streakText: String {
        switch plant.plantState {
        case .blooming: return "\(plant.currentStreak)"
        case .wilting, .dead: return "0"
        case nil: return "-"
        }
    }

    private var accessibilityStreakDescription: String {
        switch plant.plantState {
        case .blooming: return "\(plant.currentStreak) day streak"
        case .wilting, .dead: return "0 day streak"
        case nil: return "no streak data"
        }
    }

    // At accessibility sizes the streak value moves below the name and
    // status instead of being squeezed into a shrinking trailing
    // column next to them.
    private var rowLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Spacing.sm))
            : AnyLayout(HStackLayout(spacing: Theme.Spacing.md))
    }

    @ViewBuilder
    private var avatar: some View {
        if plant.isMe {
            AvatarView(
                uid: plant.id,
                name: plant.shownName,
                hasAvatar: myAvatar.hasAvatar,
                avatarUpdatedAt: myAvatar.updatedAt,
                size: 44,
                localImage: myAvatar.localImage
            )
        } else {
            AvatarView(
                uid: plant.id,
                name: plant.shownName,
                hasAvatar: plant.hasAvatar,
                avatarUpdatedAt: plant.avatarUpdatedAt,
                size: 44
            )
        }
    }

    private var identity: some View {
        HStack(spacing: Theme.Spacing.md) {
            avatar
                .overlay(alignment: .bottomTrailing) {
                    // The plant's state stays visible as a small leaf
                    // on the corner of the avatar.
                    Image(systemName: iconName)
                        .textStyle(.caption)
                        .foregroundStyle(iconColor)
                        .padding(Theme.Spacing.xs)
                        .background(Circle().fill(Theme.Colors.surfaceMuted))
                        .offset(x: 4, y: 4)
                        .accessibilityHidden(true)
                }
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(plant.shownName)
                    .textStyle(.body)
                    .fontWeight(.medium)
                if plant.displayName != nil {
                    Text("@\(plant.username)")
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text(statusWord)
                    .textStyle(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(Theme.Colors.textPrimary)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }
        }
    }

    private var streakValue: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
            Text(streakText)
                .textStyle(.heading)
                .fontWeight(.bold)
            Text("days")
                .textStyle(.caption)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
    }

    var body: some View {
        rowLayout {
            identity
            streakValue
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, isCompactHeight ? 6 : 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plant.shownName), \(statusWord.lowercased()), \(accessibilityStreakDescription)")
    }
}

#Preview("Light") {
    GreenhouseView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    GreenhouseView()
        .preferredColorScheme(.dark)
}

#Preview("Dynamic Type - Large") {
    GreenhouseView()
        .environment(\.dynamicTypeSize, .large)
}

#Preview("Dynamic Type - XXX Large") {
    GreenhouseView()
        .environment(\.dynamicTypeSize, .xxxLarge)
}

#Preview("Dynamic Type - Accessibility 5") {
    GreenhouseView()
        .environment(\.dynamicTypeSize, .accessibility5)
}
