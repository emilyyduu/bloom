import SwiftUI
import SceneKit

// The Greenhouse tab: the Shared Circle Garden. One placeholder plant
// per person (me plus up to 5 accepted friends), arranged in a circle,
// each reflecting that person's current posting streak.
struct GreenhouseView: View {
    @StateObject private var gardenService = GardenService.shared
    @State private var garden = GardenSceneBuilder.makeScene()

    private var hasFriends: Bool {
        gardenService.plants.count > 1
    }

    var body: some View {
        NavigationStack {
            Group {
                if hasFriends {
                    ZStack {
                        Color(.systemBackground)

                        SceneView(scene: garden.scene, pointOfView: garden.camera)
                            .ignoresSafeArea(edges: .bottom)

                        GardenLabelsOverlay(plants: gardenService.plants)
                    }
                } else {
                    ContentUnavailableView(
                        "No Circle Yet",
                        systemImage: "leaf",
                        description: Text("Add a friend in My Circle to start growing your shared garden.")
                    )
                }
            }
            .navigationTitle("Greenhouse")
            .task {
                FriendService.shared.startListening()
                GardenService.shared.startListening()
            }
            .onChange(of: gardenService.plants) { _, newPlants in
                GardenSceneBuilder.update(scene: garden.scene, with: newPlants)
            }
        }
    }
}

private struct GardenLabelsOverlay: View {
    let plants: [GardenPlant]

    var body: some View {
        GeometryReader { geometry in
            let center = CGPoint(x: geometry.size.width / 2, y: geometry.size.height * 0.6)
            let layoutRadius = min(geometry.size.width, geometry.size.height) * 0.32

            ForEach(Array(plants.enumerated()), id: \.element.id) { index, plant in
                let theta = GardenSceneBuilder.angle(forIndex: index, count: plants.count)
                GardenPlantLabel(plant: plant)
                    .position(
                        x: center.x + CGFloat(cos(theta)) * layoutRadius,
                        y: center.y + CGFloat(sin(theta)) * layoutRadius * 0.5
                    )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct GardenPlantLabel: View {
    let plant: GardenPlant

    var body: some View {
        VStack(spacing: 2) {
            Text(plant.username)
                .font(.caption)
                .fontWeight(.semibold)
            if plant.plantState == .blooming {
                Text("\(plant.currentStreak) day streak")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.thinMaterial, in: Capsule())
    }
}

#Preview {
    GreenhouseView()
}
