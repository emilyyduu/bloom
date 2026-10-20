#if DEBUG
import SwiftUI
import RealityKit

// RealityKit spike to compare against SceneKit for the real Greenhouse
// garden. Fully isolated: its own file, built entirely in code (no
// Reality Composer Pro / RealityKitContent package), reachable only
// from Settings' Debug section, and iOS 18 only since RealityView
// needs it while the app still targets iOS 17. Uses sample streak
// data only, never Firestore. Safe to delete this whole file, or the
// one row in SettingsView that links to it, to discard the spike.

@available(iOS 18.0, *)
private enum SpikePlant: CaseIterable {
    case blooming, wilting, dead

    // Matches the Shared Circle Garden's three PlantState cases
    // (GrowthState.swift), one placeholder person per state.
    var personName: String {
        switch self {
        case .blooming: return "Priya"
        case .wilting: return "Tom"
        case .dead: return "Mei"
        }
    }

    var stemHeight: Float {
        switch self {
        case .blooming: return 0.3
        case .wilting: return 0.18
        case .dead: return 0.08
        }
    }

    var stemRadius: Float {
        switch self {
        case .blooming: return 0.02
        case .wilting: return 0.018
        case .dead: return 0.022
        }
    }

    var stemColor: UIColor {
        switch self {
        case .blooming: return UIColor(red: 0.20, green: 0.55, blue: 0.25, alpha: 1)
        case .wilting: return UIColor(red: 0.62, green: 0.52, blue: 0.22, alpha: 1)
        case .dead: return UIColor(red: 0.40, green: 0.34, blue: 0.29, alpha: 1)
        }
    }

    var headRadius: Float? {
        switch self {
        case .blooming: return 0.08
        case .wilting: return 0.05
        case .dead: return nil
        }
    }

    var headColor: UIColor {
        switch self {
        case .blooming: return UIColor(red: 0.95, green: 0.45, blue: 0.65, alpha: 1)
        case .wilting: return UIColor(red: 0.60, green: 0.45, blue: 0.15, alpha: 1)
        case .dead: return .clear
        }
    }
}

@available(iOS 18.0, *)
private struct PlantNameComponent: Component {
    let name: String
}

@available(iOS 18.0, *)
struct RealityKitSpikeView: View {
    @State private var tappedName: String?

    var body: some View {
        ZStack {
            RealityView { content in
                content.camera = .virtual

                let root = Entity()
                content.add(root)
                root.addChild(makeGardenBed())

                let spacing: Float = 0.4
                let plants = SpikePlant.allCases
                let totalWidth = spacing * Float(plants.count - 1)
                for (index, plant) in plants.enumerated() {
                    let entity = makePlant(plant)
                    entity.position.x = Float(index) * spacing - totalWidth / 2
                    root.addChild(entity)
                }

                let light = DirectionalLight()
                light.light.intensity = 5000
                light.look(at: .zero, from: [1, 2, 1.5], relativeTo: nil)
                root.addChild(light)

                content.cameraTarget = root
            }
            .realityViewCameraControls(.orbit)
            .gesture(
                SpatialTapGesture()
                    .targetedToAnyEntity()
                    .onEnded { value in
                        tappedName = value.entity.components[PlantNameComponent.self]?.name
                    }
            )
            .background(Color(.systemBackground))

            VStack {
                Spacer()
                if let tappedName {
                    Text(tappedName)
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(.thinMaterial, in: Capsule())
                        .padding(.bottom, 32)
                        .transition(.opacity)
                }
            }
            .animation(.default, value: tappedName)
        }
        .navigationTitle("RealityKit Spike")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func makeGardenBed() -> Entity {
        let mesh = MeshResource.generateCylinder(height: 0.02, radius: 1)
        let material = SimpleMaterial(color: UIColor(red: 0.42, green: 0.32, blue: 0.22, alpha: 1), isMetallic: false)
        return ModelEntity(mesh: mesh, materials: [material])
    }

    private func makePlant(_ plant: SpikePlant) -> Entity {
        let container = Entity()

        let stemMesh = MeshResource.generateCylinder(height: plant.stemHeight, radius: plant.stemRadius)
        let stemMaterial = SimpleMaterial(color: plant.stemColor, isMetallic: false)
        let stem = ModelEntity(mesh: stemMesh, materials: [stemMaterial])
        stem.position.y = 0.01 + plant.stemHeight / 2
        container.addChild(stem)

        var topOfPlant = 0.01 + plant.stemHeight
        if let headRadius = plant.headRadius {
            let headMesh = MeshResource.generateSphere(radius: headRadius)
            let headMaterial = SimpleMaterial(color: plant.headColor, isMetallic: false)
            let head = ModelEntity(mesh: headMesh, materials: [headMaterial])
            head.position.y = topOfPlant + headRadius * 0.6
            container.addChild(head)
            topOfPlant += headRadius * 1.2
        }

        container.components.set(PlantNameComponent(name: plant.personName))
        container.components.set(InputTargetComponent())
        let collisionShape = ShapeResource.generateSphere(radius: max(topOfPlant, 0.1))
            .offsetBy(translation: [0, topOfPlant / 2, 0])
        container.components.set(CollisionComponent(shapes: [collisionShape]))

        return container
    }
}

struct RealityKitSpikeEntryRow: View {
    var body: some View {
        if #available(iOS 18.0, *) {
            NavigationLink("RealityKit Spike") {
                RealityKitSpikeView()
            }
        } else {
            EmptyView()
        }
    }
}

@available(iOS 18.0, *)
#Preview("Light") {
    NavigationStack {
        RealityKitSpikeView()
    }
    .preferredColorScheme(.light)
}

@available(iOS 18.0, *)
#Preview("Dark") {
    NavigationStack {
        RealityKitSpikeView()
    }
    .preferredColorScheme(.dark)
}
#endif
