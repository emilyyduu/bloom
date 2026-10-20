import SwiftUI

// The Greenhouse tab. Week 10 scope is streaks from real data behind a
// placeholder card, not the SceneKit scene itself (see
// GardenSceneBuilder.swift, which this view no longer uses but keeps

struct GreenhouseView: View {
    var body: some View {
        Text("Greenhouse")
    }
}
//    @StateObject private var gardenService = GardenService.shared
//    @Environment(\.colorScheme) private var colorScheme
//
//    #if DEBUG
//    @AppStorage("gardenSampleDataEnabled") private var isSampleDataEnabled = false
//    #endif
//
//    private var plants: [GardenPlant] {
//        #if DEBUG
//        if isSampleDataEnabled { return Self.samplePlants }
//        #endif
//        return gardenService.plants
//    }
//
//    // Me first, then everyone else ordered by streak, highest first.
//    // "No data" sorts last, below a 0 day wilted or withered streak.
//    private var sortedPlants: [GardenPlant] {
//        guard let me = plants.first else { return [] }
//        let others = plants.dropFirst().sorted { displayStreak(for: $0) > displayStreak(for: $1) }
//        return [me] + others
//    }
//
//    private var showsAddFriendsHint: Bool {
//        #if DEBUG
//        if isSampleDataEnabled { return false }
//        #endif
//        return plants.count <= 1
//    }
//
//    private func displayStreak(for plant: GardenPlant) -> Int {
//        switch plant.plantState {
//        case .blooming: return plant.currentStreak
//        case .wilting, .dead: return 0
//        case nil: return -1
//        }
//    }
//
//    var body: some View {
//        NavigationStack {
//            ScrollView {
//                VStack(alignment: .leading, spacing: 24) {
//                    myCirclePill
//
//                    gardenPlaceholderCard
//
//                    Text("VIEW STREAKS")
//                        .font(.caption)
//                        .fontWeight(.semibold)
//                        .tracking(1.5)
//                        .foregroundStyle(.secondary)
//
//                    streaksCard
//
//                    if showsAddFriendsHint {
//                        Text("Add friends from Profile to grow your shared garden.")
//                            .font(.footnote)
//                            .foregroundStyle(.secondary)
//                    }
//                }
//                .padding()
//            }
//            .navigationTitle("Greenhouse")
//            .navigationBarTitleDisplayMode(.large)
//            .task {
//                FriendService.shared.startListening()
//                GardenService.shared.startListening()
//            }
//        }
//    }
//
//    private var myCirclePill: some View {
//        Text("My Circle")
//            .font(.subheadline)
//            .fontWeight(.medium)
//            .padding(.horizontal, 12)
//            .padding(.vertical, 6)
//            .background(Color(.secondarySystemBackground), in: Capsule())
//    }
//
//    // Placeholder for the future 3D SceneKit garden. Swap this card's
//    // contents for a GardenSceneView (built on GardenSceneBuilder)
//    // once that's brought back.
//    private var gardenPlaceholderCard: some View {
//        RoundedRectangle(cornerRadius: 28)
//            .fill(Color.green.opacity(colorScheme == .dark ? 0.22 : 0.14))
//            .aspectRatio(1, contentMode: .fit)
//            .overlay {
//                VStack(spacing: 12) {
//                    Image(systemName: "leaf.fill")
//                        .font(.system(size: 56))
//                        .foregroundStyle(.green)
//                    Text("3D garden - later implementation")
//                        .font(.headline)
//                        .foregroundStyle(.secondary)
//                }
//            }
//    }
//
//    private var streaksCard: some View {
//        VStack(spacing: 0) {
//            ForEach(Array(sortedPlants.enumerated()), id: \.element.id) { index, plant in
//                GardenStreakRow(plant: plant)
//                if index < sortedPlants.count - 1 {
//                    Divider().padding(.leading, 72)
//                }
//            }
//        }
//        .padding(.vertical, 4)
//        .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
//        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color(.separator), lineWidth: 1))
//    }
//
//    #if DEBUG
//    private static let samplePlants: [GardenPlant] = [
//        GardenPlant(id: "sample-blooming-1", username: "Maya", currentStreak: 14, plantState: .blooming),
//        GardenPlant(id: "sample-blooming-2", username: "Theo", currentStreak: 21, plantState: .blooming),
//        GardenPlant(id: "sample-wilting", username: "Priya", currentStreak: 6, plantState: .wilting),
//        GardenPlant(id: "sample-dead", username: "Sam", currentStreak: 2, plantState: .dead),
//        GardenPlant(id: "sample-none", username: "Jordan", currentStreak: 0, plantState: nil),
//    ]
//    #endif
//}
//
//private struct GardenStreakRow: View {
//    let plant: GardenPlant
//
//    private var statusWord: String {
//        switch plant.plantState {
//        case .blooming: return "Blooming"
//        case .wilting: return "Wilting"
//        case .dead: return "Withered"
//        case nil: return "No posts yet"
//        }
//    }
//
//    private var iconName: String {
//        plant.plantState == nil ? "leaf" : "leaf.fill"
//    }
//
//    private var iconColor: Color {
//        switch plant.plantState {
//        case .blooming: return .green
//        case .wilting: return Color(red: 0.62, green: 0.52, blue: 0.22)
//        case .dead: return .gray
//        case nil: return .secondary
//        }
//    }
//
//    private var streakText: String {
//        switch plant.plantState {
//        case .blooming: return "\(plant.currentStreak)"
//        case .wilting, .dead: return "0"
//        case nil: return "-"
//        }
//    }
//
//    private var accessibilityStreakDescription: String {
//        switch plant.plantState {
//        case .blooming: return "\(plant.currentStreak) day streak"
//        case .wilting, .dead: return "0 day streak"
//        case nil: return "no streak data"
//        }
//    }
//
//    var body: some View {
//        HStack(spacing: 12) {
//            ZStack {
//                Circle().fill(iconColor.opacity(0.15))
//                Image(systemName: iconName)
//                    .foregroundStyle(iconColor)
//                    .font(.headline)
//            }
//            .frame(width: 44, height: 44)
//
//            VStack(alignment: .leading, spacing: 2) {
//                Text(plant.username)
//                    .font(.body)
//                    .fontWeight(.medium)
//                Text(statusWord)
//                    .font(.caption)
//                    .foregroundStyle(.secondary)
//            }
//
//            Spacer()
//
//            VStack(alignment: .trailing, spacing: 0) {
//                Text(streakText)
//                    .font(.title3)
//                    .fontWeight(.bold)
//                Text("days")
//                    .font(.caption2)
//                    .foregroundStyle(.secondary)
//            }
//        }
//        .padding(.horizontal, 16)
//        .padding(.vertical, 10)
//        .accessibilityElement(children: .combine)
//        .accessibilityLabel("\(plant.username), \(statusWord.lowercased()), \(accessibilityStreakDescription)")
//    }
//}
//
//#Preview {
//    GreenhouseView()
//}
