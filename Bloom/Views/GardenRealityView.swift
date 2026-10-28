import SwiftUI
import RealityKit

// The Shared Circle Garden, built in code with RealityKit (no Reality
// Composer Pro package). Each person gets one plant at a fixed slot
// around a garden bed; slots are assigned by sorting uids so nobody
// moves between launches. `isInteractive` controls whether orbit and
// tap are enabled: false for the small card on the Greenhouse tab
// (where a finger starting on the card should still scroll the page),
// true for the full screen cover.
struct GardenRealityView: View {
    let plants: [GardenPlant]
    var isInteractive: Bool = false
    var onSelectPlant: ((GardenPlant) -> Void)?

    @Environment(\.colorScheme) private var colorScheme
    @State private var coordinator = GardenSceneCoordinator()

    var body: some View {
        Group {
            if isInteractive {
                realityView
                    .realityViewCameraControls(.orbit)
                    .gesture(tapGesture)
            } else {
                realityView
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var realityView: some View {
        RealityView { content in
            content.camera = .virtual
            let root = coordinator.makeRoot(colorScheme: colorScheme)
            content.add(root)
            content.cameraTarget = root
            coordinator.sync(plants: plants)
        } update: { _ in
            coordinator.updateAppearance(colorScheme: colorScheme)
            coordinator.sync(plants: plants)
        }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                guard let plant = coordinator.plant(forEntity: value.entity) else { return }
                onSelectPlant?(plant)
            }
    }

    private func stateWord(_ state: PlantState?) -> String {
        switch state {
        case .blooming: return "blooming"
        case .wilting: return "wilting"
        case .dead: return "withered"
        case nil: return "no posts yet"
        }
    }

    private var accessibilitySummary: String {
        guard let me = plants.first else { return "Garden with no plants yet." }
        let count = plants.count
        var sentences = ["Garden with \(count) plant\(count == 1 ? "" : "s")."]
        sentences.append("You: \(stateWord(me.plantState)).")
        for friend in plants.dropFirst() {
            sentences.append("\(friend.username): \(stateWord(friend.plantState)).")
        }
        return sentences.joined(separator: " ")
    }
}

// Full screen interactive garden, opened by tapping the Greenhouse
// card. Owns its own Close button and the chip shown when a plant is
// tapped.
struct FullScreenGardenView: View {
    let plants: [GardenPlant]

    @Environment(\.dismiss) private var dismiss
    @State private var selectedPlant: GardenPlant?

    var body: some View {
        NavigationStack {
            GardenRealityView(plants: plants, isInteractive: true) { plant in
                selectedPlant = plant
            }
            .background(Color(.systemBackground))
            .overlay(alignment: .bottom) {
                if let selectedPlant {
                    PlantInfoChip(plant: selectedPlant)
                        .padding(.bottom, 24)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: selectedPlant?.id)
            .navigationTitle("Garden")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }
}

private struct PlantInfoChip: View {
    let plant: GardenPlant

    private var stateWord: String {
        switch plant.plantState {
        case .blooming: return "Blooming"
        case .wilting: return "Wilting"
        case .dead: return "Withered"
        case nil: return "No posts yet"
        }
    }

    private var streakText: String {
        switch plant.plantState {
        case .blooming: return "\(plant.currentStreak) day streak"
        case .wilting, .dead: return "0 day streak"
        case nil: return "No streak yet"
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(plant.username)
                .font(.headline)
            Text(stateWord)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text(streakText)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
        .padding(.horizontal, 24)
    }
}

// Owns the RealityKit entity graph across repeated `update` calls: the
// static bed, light and camera target are built once, plants are
// added, restyled or removed by diffing against the previous sync.
@MainActor
final class GardenSceneCoordinator {
    private static let slotCount = 6
    private static let slotRadius: Float = 0.6

    private var root: Entity?
    private var bedEntity: ModelEntity?
    private var plantEntities: [String: Entity] = [:]
    private var plantStates: [String: PlantState?] = [:]
    private var plantLookup: [String: GardenPlant] = [:]

    // Builds the bed and light once and returns the root entity for
    // the caller to add to the RealityView's content and use as the
    // camera target. Safe to call more than once; only builds once.
    func makeRoot(colorScheme: ColorScheme) -> Entity {
        if let root { return root }

        let root = Entity()
        self.root = root

        let bed = GardenGeometry.makeBed(colorScheme: colorScheme)
        root.addChild(bed)
        bedEntity = bed

        let light = DirectionalLight()
        light.light.intensity = 5000
        light.look(at: .zero, from: [1, 2, 1.5], relativeTo: nil)
        root.addChild(light)

        return root
    }

    func updateAppearance(colorScheme: ColorScheme) {
        guard let bedEntity else { return }
        GardenGeometry.updateBedMaterial(bedEntity, colorScheme: colorScheme)
    }

    func sync(plants: [GardenPlant]) {
        guard let root else { return }

        let capped = Array(plants.prefix(Self.slotCount))
        let sortedIDs = capped.map(\.id).sorted()
        var currentIDs = Set<String>()

        for plant in capped {
            currentIDs.insert(plant.id)
            plantLookup[plant.id] = plant
            let slot = sortedIDs.firstIndex(of: plant.id) ?? 0
            let position = Self.position(forSlot: slot)

            if let existing = plantEntities[plant.id] {
                existing.position = position
                if plantStates[plant.id] != Optional(plant.plantState) {
                    existing.removeFromParent()
                    let replacement = GardenGeometry.makeEntity(for: plant.plantState, plantID: plant.id)
                    replacement.position = position
                    root.addChild(replacement)
                    plantEntities[plant.id] = replacement
                    plantStates[plant.id] = plant.plantState
                }
            } else {
                let entity = GardenGeometry.makeEntity(for: plant.plantState, plantID: plant.id)
                entity.position = position
                root.addChild(entity)
                plantEntities[plant.id] = entity
                plantStates[plant.id] = plant.plantState
            }
        }

        for id in plantEntities.keys where !currentIDs.contains(id) {
            plantEntities[id]?.removeFromParent()
            plantEntities.removeValue(forKey: id)
            plantStates.removeValue(forKey: id)
            plantLookup.removeValue(forKey: id)
        }
    }

    func plant(forEntity entity: Entity) -> GardenPlant? {
        var current: Entity? = entity
        while let candidate = current {
            if let id = candidate.components[PlantIdentifierComponent.self]?.plantID {
                return plantLookup[id]
            }
            current = candidate.parent
        }
        return nil
    }

    private static func position(forSlot slot: Int) -> SIMD3<Float> {
        let angle = (Float(slot) / Float(slotCount)) * 2 * .pi
        return SIMD3<Float>(slotRadius * cos(angle), 0, slotRadius * sin(angle))
    }
}

private struct PlantIdentifierComponent: Component {
    let plantID: String
}

// Placeholder geometry for the garden, factored one per PlantState
// plus a nil case for an empty plot. Meshes and materials are built
// once and shared across every plant entity in that state.
private enum GardenGeometry {
    private static let bedMesh = MeshResource.generateCylinder(height: 0.02, radius: 1)

    private static let moundMesh = MeshResource.generateSphere(radius: 0.07)
    private static let moundMaterial = SimpleMaterial(
        color: UIColor(red: 0.33, green: 0.24, blue: 0.16, alpha: 1),
        isMetallic: false
    )

    private static let stemMeshes: [PlantState: MeshResource] = [
        .blooming: .generateCylinder(height: 0.3, radius: 0.02),
        .wilting: .generateCylinder(height: 0.18, radius: 0.018),
        .dead: .generateCylinder(height: 0.08, radius: 0.022)
    ]

    private static let headMeshes: [PlantState: MeshResource] = [
        .blooming: .generateSphere(radius: 0.08),
        .wilting: .generateSphere(radius: 0.05)
    ]

    private static let stemMaterials: [PlantState: SimpleMaterial] = [
        .blooming: SimpleMaterial(color: UIColor(Theme.Colors.blooming), isMetallic: false),
        .wilting: SimpleMaterial(color: UIColor(Theme.Colors.wilting), isMetallic: false),
        .dead: SimpleMaterial(color: UIColor(Theme.Colors.dead), isMetallic: false)
    ]

    static func makeBed(colorScheme: ColorScheme) -> ModelEntity {
        let bed = ModelEntity(mesh: bedMesh, materials: [bedMaterial(for: colorScheme)])
        return bed
    }

    static func updateBedMaterial(_ bed: ModelEntity, colorScheme: ColorScheme) {
        bed.model?.materials = [bedMaterial(for: colorScheme)]
    }

    private static func bedMaterial(for colorScheme: ColorScheme) -> SimpleMaterial {
        let color: UIColor = colorScheme == .dark
            ? UIColor(red: 0.30, green: 0.22, blue: 0.14, alpha: 1)
            : UIColor(red: 0.42, green: 0.32, blue: 0.22, alpha: 1)
        return SimpleMaterial(color: color, isMetallic: false)
    }

    static func makeEntity(for state: PlantState?, plantID: String) -> Entity {
        let container = Entity()
        var topOfPlant: Float = 0.01

        if let state {
            guard let stemMesh = stemMeshes[state], let stemMaterial = stemMaterials[state] else {
                return container
            }
            let stem = ModelEntity(mesh: stemMesh, materials: [stemMaterial])
            let stemHeight = stemHeight(for: state)
            stem.position.y = 0.01 + stemHeight / 2
            container.addChild(stem)
            topOfPlant = 0.01 + stemHeight

            if let headMesh = headMeshes[state] {
                let headRadius = headRadius(for: state)
                let head = ModelEntity(mesh: headMesh, materials: [stemMaterial])
                head.position.y = topOfPlant + headRadius * 0.6
                container.addChild(head)
                topOfPlant += headRadius * 1.2
            }
        } else {
            let mound = ModelEntity(mesh: moundMesh, materials: [moundMaterial])
            mound.scale = SIMD3<Float>(1, 0.35, 1)
            mound.position.y = 0.01
            container.addChild(mound)
            topOfPlant = 0.04
        }

        container.components.set(PlantIdentifierComponent(plantID: plantID))
        container.components.set(InputTargetComponent())
        let collisionShape = ShapeResource.generateSphere(radius: max(topOfPlant, 0.1))
            .offsetBy(translation: [0, topOfPlant / 2, 0])
        container.components.set(CollisionComponent(shapes: [collisionShape]))

        return container
    }

    private static func stemHeight(for state: PlantState) -> Float {
        switch state {
        case .blooming: return 0.3
        case .wilting: return 0.18
        case .dead: return 0.08
        }
    }

    private static func headRadius(for state: PlantState) -> Float {
        switch state {
        case .blooming: return 0.08
        case .wilting: return 0.05
        case .dead: return 0
        }
    }
}

#if DEBUG
private let gardenPreviewPlants: [GardenPlant] = [
    GardenPlant(id: "preview-you", username: "You", currentStreak: 14, plantState: .blooming),
    GardenPlant(id: "preview-wilting", username: "Tom", currentStreak: 3, plantState: .wilting),
    GardenPlant(id: "preview-dead", username: "Mei", currentStreak: 0, plantState: .dead),
    GardenPlant(id: "preview-none", username: "Jordan", currentStreak: 0, plantState: nil)
]

#Preview("Light") {
    GardenRealityView(plants: gardenPreviewPlants)
        .frame(width: 320, height: 320)
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    GardenRealityView(plants: gardenPreviewPlants)
        .frame(width: 320, height: 320)
        .preferredColorScheme(.dark)
}

#Preview("Full Screen") {
    FullScreenGardenView(plants: gardenPreviewPlants)
}

#Preview("Dynamic Type - Accessibility 5") {
    FullScreenGardenView(plants: gardenPreviewPlants)
        .environment(\.dynamicTypeSize, .accessibility5)
}
#endif
