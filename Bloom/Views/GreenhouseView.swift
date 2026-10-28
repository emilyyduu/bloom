import SwiftUI

// The Greenhouse tab. The garden is a RealityKit scene (GardenRealityView):
// a small, non-interactive preview sits in the card below, and tapping
// it opens a full screen interactive version.
struct GreenhouseView: View {
    @StateObject private var gardenService = GardenService.shared
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @State private var isShowingFullScreenGarden = false

    // In landscape on iPhone (compact height) the garden card and the
    // streaks list sit side by side instead of one on top of the
    // other, but both still scroll together in the one ScrollView.
    private var isCompactHeight: Bool { verticalSizeClass == .compact }

    private var panesLayout: AnyLayout {
        isCompactHeight
            ? AnyLayout(HStackLayout(alignment: .top, spacing: 0))
            : AnyLayout(VStackLayout(spacing: 0))
    }

    #if DEBUG
    @AppStorage("gardenSampleDataEnabled") private var isSampleDataEnabled = false
    #endif

    private var plants: [GardenPlant] {
        #if DEBUG
        if isSampleDataEnabled { return Self.samplePlants }
        #endif
        return gardenService.plants
    }

    // Me first, then everyone else ordered by streak, highest first.
    // "No data" sorts last, below a 0 day wilted or withered streak.
    private var sortedPlants: [GardenPlant] {
        guard let me = plants.first else { return [] }
        let others = plants.dropFirst().sorted { displayStreak(for: $0) > displayStreak(for: $1) }
        return [me] + others
    }

    private var showsAddFriendsHint: Bool {
        #if DEBUG
        if isSampleDataEnabled { return false }
        #endif
        return plants.count <= 1
    }

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
            .navigationTitle("Greenhouse")
            .toolbar(.hidden, for: .navigationBar)
            .task {
                FriendService.shared.startListening()
                GardenService.shared.startListening()
            }
            .fullScreenCover(isPresented: $isShowingFullScreenGarden) {
                FullScreenGardenView(plants: plants)
            }
        }
    }

    private var gardenPane: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 16) {
            myCirclePill
            gardenCard
        }
        .padding(isCompactHeight ? 10 : 16)
        .frame(maxWidth: isCompactHeight ? 340 : .infinity)
    }

    private var streaksPane: some View {
        VStack(alignment: .leading, spacing: isCompactHeight ? 10 : 16) {
            Text("VIEW STREAKS")
                .font(.caption)
                .fontWeight(.semibold)
                .tracking(1.5)
                .foregroundStyle(.secondary)

            streaksCard

            if showsAddFriendsHint {
                Text("Add friends from Profile to grow your shared garden.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(isCompactHeight ? 10 : 16)
        .frame(maxWidth: .infinity)
    }

    private var myCirclePill: some View {
        Text("My Circle")
            .font(.subheadline)
            .fontWeight(.medium)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(.secondarySystemBackground), in: Capsule())
    }

    // The real RealityKit garden, shown small and non-interactive
    // here so the page still scrolls when a finger starts on the
    // card. Tapping it opens the full screen interactive version.
    private var gardenCard: some View {
        RoundedRectangle(cornerRadius: 28)
            .fill(Theme.Colors.gardenCardBackground)
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: isCompactHeight ? 260 : .infinity)
            .overlay {
                GardenRealityView(plants: plants)
                    .padding(8)
            }
            .overlay(alignment: .topTrailing) {
                Image(systemName: "arrow.up.left.and.arrow.down.right")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(8)
                    .background(.thinMaterial, in: Circle())
                    .padding(10)
                    .accessibilityHidden(true)
            }
            .clipShape(RoundedRectangle(cornerRadius: 28))
            .contentShape(RoundedRectangle(cornerRadius: 28))
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
        .padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1))
    }

    #if DEBUG
    private static let samplePlants: [GardenPlant] = [
        GardenPlant(id: "sample-blooming-1", username: "Maya", currentStreak: 14, plantState: .blooming),
        GardenPlant(id: "sample-blooming-2", username: "Theo", currentStreak: 21, plantState: .blooming),
        GardenPlant(id: "sample-wilting", username: "Priya", currentStreak: 6, plantState: .wilting),
        GardenPlant(id: "sample-dead", username: "Sam", currentStreak: 2, plantState: .dead),
        GardenPlant(id: "sample-none", username: "Jordan", currentStreak: 0, plantState: nil),
    ]
    #endif
}

private struct GardenStreakRow: View {
    let plant: GardenPlant

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @ScaledMetric(relativeTo: .body) private var iconDiameter: CGFloat = 44

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
        case nil: return .secondary
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
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    private var identity: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(iconColor.opacity(0.22))
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.headline)
            }
            .frame(width: iconDiameter, height: iconDiameter)

            VStack(alignment: .leading, spacing: 2) {
                Text(plant.username)
                    .font(.body)
                    .fontWeight(.medium)
                Text(statusWord)
                    .font(.caption)
                    .fontWeight(.medium)
                    .foregroundStyle(.primary)
            }

            if !dynamicTypeSize.isAccessibilitySize {
                Spacer()
            }
        }
    }

    private var streakValue: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 0) {
            Text(streakText)
                .font(.title3)
                .fontWeight(.bold)
            Text("days")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : nil, alignment: .leading)
    }

    var body: some View {
        rowLayout {
            identity
            streakValue
        }
        .padding(.horizontal, 16)
        .padding(.vertical, isCompactHeight ? 6 : 10)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(plant.username), \(statusWord.lowercased()), \(accessibilityStreakDescription)")
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
