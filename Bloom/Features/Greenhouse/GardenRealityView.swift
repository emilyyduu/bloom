import SwiftUI
import RealityKit
import UIKit

// The Shared Garden: a small square island floating in space, built in
// code with RealityKit. Each person gets one flower on the island, and
// how it looks depends on their streak.
//
// Full screen controls:
//   - Drag to turn the island.
//   - Pinch out on a flower to fly in and see whose it is.
//   - Tap a flower to jump straight to it.
//   - Pinch in, or tap the close button, to go back to the whole island.
//
// The small card on the Greenhouse tab uses the same scene with
// gestures switched off, so the page still scrolls, and slowly turns
// on its own.

// MARK: - Visual stages

// What a plant looks like. Worked out from PlantState (how long since
// the last post) plus the streak length, so a long streak looks
// noticeably different from a new one.
enum GardenStage: Equatable {
    case empty      // no posts yet: a bare soil mound
    case sprout     // blooming, streak 1 to 2: two little leaves
    case bud        // blooming, streak 3 to 6: closed bud
    case flower     // blooming, streak 7 to 13: open flower
    case fullBloom  // blooming, streak 14+: big flower with two side flowers
    case wilting    // 2 to 4 days since posting: drooping, faded
    case withered   // 5+ days: snapped brown stem, fallen petals

    init(state: PlantState?, streak: Int) {
        switch state {
        case nil: self = .empty
        case .dead: self = .withered
        case .wilting: self = .wilting
        case .blooming:
            switch streak {
            case ..<3: self = .sprout
            case 3..<7: self = .bud
            case 7..<14: self = .flower
            default: self = .fullBloom
            }
        }
    }

    var title: String {
        switch self {
        case .empty: "Not planted yet"
        case .sprout: "Sprouting"
        case .bud: "Budding"
        case .flower: "In bloom"
        case .fullBloom: "Full bloom"
        case .wilting: "Wilting"
        case .withered: "Withered"
        }
    }

    // Roughly how tall the plant is, used to aim the camera when you
    // fly in to it and to size its tap target.
    var height: Float {
        switch self {
        case .empty: 0.06
        case .sprout: 0.12
        case .bud: 0.3
        case .flower: 0.36
        case .fullBloom: 0.44
        case .wilting: 0.24
        case .withered: 0.12
        }
    }
}

// MARK: - Garden view

struct GardenRealityView: View {
    let plants: [GardenPlant]
    // The name in the VoiceOver summary: All friends or a circle's name.
    var selectionName: String = "All friends"
    var isInteractive: Bool = false

    @State private var coordinator = GardenSceneCoordinator()

    var body: some View {
        GeometryReader { geometry in
            realityView
                .gesture(tapGesture, including: isInteractive ? .all : .none)
                .simultaneousGesture(orbitGesture(viewSize: geometry.size), including: isInteractive ? .all : .none)
        }
        .overlay(alignment: .top) {
            if isInteractive && coordinator.focusedPlantID == nil && !plants.isEmpty {
                Text("Pinch into a flower to see whose it is")
                    .textStyle(.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .padding(.top, Theme.Spacing.md)
                    .transition(.opacity)
                    .accessibilityHidden(true)
            }
        }
        .overlay(alignment: .bottom) {
            if isInteractive, let plant = focusedPlant {
                PlantNameCard(plant: plant) {
                    coordinator.clearFocus()
                }
                .padding(.bottom, Theme.Spacing.xl)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.25), value: coordinator.focusedPlantID)
        .accessibilityElement(children: isInteractive ? .contain : .ignore)
        .accessibilityLabel(accessibilitySummary)
    }

    private var focusedPlant: GardenPlant? {
        guard let id = coordinator.focusedPlantID else { return nil }
        return plants.first { $0.id == id }
    }

    private var realityView: some View {
        RealityView { [coordinator] content in
            content.camera = .virtual
            let root = coordinator.makeRoot()
            content.add(root)
            coordinator.sync(plants: plants)
            coordinator.updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in
                let delta = Float(event.deltaTime)
                MainActor.assumeIsolated {
                    coordinator.tick(delta)
                }
            }
        } update: { [coordinator] _ in
            coordinator.sync(plants: plants)
        }
    }

    private var tapGesture: some Gesture {
        SpatialTapGesture()
            .targetedToAnyEntity()
            .onEnded { value in
                coordinator.focus(onEntity: value.entity)
            }
    }

    private func orbitGesture(viewSize: CGSize) -> some Gesture {
        let drag = DragGesture(minimumDistance: 6)
            .onChanged { value in coordinator.dragChanged(value.translation) }
            .onEnded { _ in coordinator.dragEnded() }

        let pinch = MagnifyGesture()
            .onChanged { value in
                coordinator.pinchChanged(
                    magnification: value.magnification,
                    startLocation: value.startLocation,
                    viewSize: viewSize
                )
            }
            .onEnded { _ in coordinator.pinchEnded() }

        return drag.simultaneously(with: pinch)
    }

    private var accessibilitySummary: String {
        guard !plants.isEmpty else { return "Garden for \(selectionName) with no plants yet." }
        let count = plants.count
        var sentences = ["Garden for \(selectionName) with \(count) plant\(count == 1 ? "" : "s")."]
        for plant in plants {
            let stage = GardenStage(state: plant.plantState, streak: plant.currentStreak)
            let name = plant.isMe ? "You" : (plant.displayName ?? plant.username)
            sentences.append("\(name): \(stage.title.lowercased()).")
        }
        return sentences.joined(separator: " ")
    }
}

// Full screen interactive garden, opened by tapping the Greenhouse card.
struct FullScreenGardenView: View {
    let plants: [GardenPlant]
    var selectionName: String = "All friends"

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            GardenRealityView(plants: plants, selectionName: selectionName, isInteractive: true)
                .background(Theme.Colors.background)
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

// Shown at the bottom when you've flown in to someone's flower. Looks
// the same whether you got there by pinching or tapping.
private struct PlantNameCard: View {
    let plant: GardenPlant
    var onClose: () -> Void

    private var stage: GardenStage {
        GardenStage(state: plant.plantState, streak: plant.currentStreak)
    }

    private var name: String {
        plant.isMe ? "You" : (plant.displayName ?? plant.username)
    }

    private var streakText: String {
        switch plant.plantState {
        case .blooming: "\(plant.currentStreak) day streak"
        case .wilting, .dead: "0 day streak"
        case nil: "No posts yet"
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .textStyle(.heading)
                    .foregroundStyle(Theme.Colors.textPrimary)
                if !plant.isMe, plant.displayName != nil {
                    Text("@\(plant.username)")
                        .textStyle(.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                }
                Text("\(stage.title), \(streakText)")
                    .textStyle(.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
            Spacer(minLength: 0)
            Button(action: onClose) {
                Image(systemName: "xmark")
            }
            .buttonStyle(CircleIconButtonStyle(fill: Theme.Colors.surfaceMuted))
            .accessibilityLabel("Back to the whole garden")
        }
        .card(radius: Theme.Radius.large)
        .padding(.horizontal, Theme.Spacing.screenEdge)
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Scene coordinator

// Owns the RealityKit entity graph and the camera. The island, lights
// and camera are built once; plants are added, rebuilt or removed by
// diffing against the previous sync. All camera movement eases towards
// a target every frame, so pinches and taps glide rather than jump.
@MainActor
@Observable
final class GardenSceneCoordinator {
    // The plant the camera has flown in to, if any. The only thing
    // SwiftUI watches.
    private(set) var focusedPlantID: String?

    @ObservationIgnored var updateSubscription: EventSubscription?

    @ObservationIgnored private var root: Entity?
    @ObservationIgnored private var island: Entity?
    @ObservationIgnored private var camera: PerspectiveCamera?
    @ObservationIgnored private var plantEntities: [String: Entity] = [:]
    @ObservationIgnored private var plantStages: [String: GardenStage] = [:]
    @ObservationIgnored private var plantLookup: [String: GardenPlant] = [:]
    @ObservationIgnored private var plantTurn: [String: Float] = [:]

    // Camera, as an orbit around `target`. Current values ease towards
    // the target values every frame.
    @ObservationIgnored private var yaw: Float = 0.7
    @ObservationIgnored private var pitch: Float = 0.5
    @ObservationIgnored private var distance: Float = 4.6
    @ObservationIgnored private var target = SIMD3<Float>(0, 0.08, 0)
    @ObservationIgnored private var targetYaw: Float = 0.7
    @ObservationIgnored private var targetPitch: Float = 0.5
    @ObservationIgnored private var targetDistance: Float = 4.6

    @ObservationIgnored private var time: Float = 0
    @ObservationIgnored private var autoRotate = true

    // Gesture state
    @ObservationIgnored private var lastDrag: CGSize = .zero
    @ObservationIgnored private var isPinching = false
    @ObservationIgnored private var pinchStartDistance: Float?
    @ObservationIgnored private var pinchCandidateID: String?

    private static let maxPlants = GardenService.maxPlants
    private static let fieldOfView: Float = 35
    private static let defaultDistance: Float = 4.6
    private static let minDistance: Float = 0.55
    private static let maxDistance: Float = 7
    private static let visitDistance: Float = 1.0
    // Zooming closer than this picks a flower; zooming back out past
    // the second value lets it go. The gap stops it flickering.
    private static let focusInDistance: Float = 2.2
    private static let focusOutDistance: Float = 2.9

    func makeRoot() -> Entity {
        if let root { return root }

        let root = Entity()
        self.root = root

        let island = Entity()
        island.addChild(GardenModels.makeIsland())
        root.addChild(island)
        self.island = island

        let sun = DirectionalLight()
        sun.light.intensity = 4500
        sun.shadow = DirectionalLightComponent.Shadow(maximumDistance: 5, depthBias: 1)
        sun.look(at: .zero, from: [1.2, 2.4, 1.6], relativeTo: nil)
        root.addChild(sun)

        let fill = DirectionalLight()
        fill.light.intensity = 1600
        fill.look(at: .zero, from: [-1.5, 1, -1], relativeTo: nil)
        root.addChild(fill)

        let camera = PerspectiveCamera()
        camera.camera.fieldOfViewInDegrees = Self.fieldOfView
        root.addChild(camera)
        self.camera = camera

        tick(0)
        return root
    }

    // MARK: Plants

    func sync(plants: [GardenPlant]) {
        guard let island else { return }

        let capped = Array(plants.prefix(Self.maxPlants))
        let sortedIDs = capped.map(\.id).sorted()
        let layout = GardenModels.layout(ids: sortedIDs)
        var currentIDs = Set<String>()

        for plant in capped {
            currentIDs.insert(plant.id)
            plantLookup[plant.id] = plant
            let stage = GardenStage(state: plant.plantState, streak: plant.currentStreak)
            let position = layout[plant.id] ?? .zero

            if let existing = plantEntities[plant.id], plantStages[plant.id] == stage {
                existing.position = position
            } else {
                plantEntities[plant.id]?.removeFromParent()
                let entity = GardenModels.makePlant(stage: stage, plantID: plant.id)
                entity.position = position
                island.addChild(entity)
                plantEntities[plant.id] = entity
                plantStages[plant.id] = stage
                plantTurn[plant.id] = GardenModels.unit(plant.id, salt: 7) * 2 * .pi
            }
        }

        for id in Array(plantEntities.keys) where !currentIDs.contains(id) {
            plantEntities[id]?.removeFromParent()
            plantEntities.removeValue(forKey: id)
            plantStages.removeValue(forKey: id)
            plantLookup.removeValue(forKey: id)
            plantTurn.removeValue(forKey: id)
        }

        if let focusedPlantID, plantEntities[focusedPlantID] == nil {
            self.focusedPlantID = nil
        }
    }

    // MARK: Gestures

    func focus(onEntity entity: Entity) {
        guard let id = plantID(forEntity: entity) else { return }
        autoRotate = false
        focusedPlantID = id
        targetDistance = Self.visitDistance
    }

    func clearFocus() {
        focusedPlantID = nil
        targetDistance = Self.defaultDistance
    }

    func dragChanged(_ translation: CGSize) {
        autoRotate = false
        defer { lastDrag = translation }
        // Two fingers pinching also move a little; don't spin the
        // island while that's happening.
        guard !isPinching else { return }
        let dx = Float(translation.width - lastDrag.width)
        let dy = Float(translation.height - lastDrag.height)
        targetYaw -= dx * 0.008
        targetPitch = min(max(targetPitch + dy * 0.006, 0.12), 1.3)
    }

    func dragEnded() {
        lastDrag = .zero
    }

    func pinchChanged(magnification: CGFloat, startLocation: CGPoint, viewSize: CGSize) {
        autoRotate = false
        if pinchStartDistance == nil {
            isPinching = true
            pinchStartDistance = targetDistance
            // The flower under your fingers when the pinch started, if any.
            pinchCandidateID = plantID(at: startLocation, in: viewSize, maxAngle: 0.2)
        }

        let start = pinchStartDistance ?? targetDistance
        let zoom = max(Float(magnification), 0.01)
        targetDistance = min(max(start / zoom, Self.minDistance), Self.maxDistance)

        if focusedPlantID == nil, targetDistance < Self.focusInDistance {
            let centre = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
            focusedPlantID = pinchCandidateID ?? plantID(at: centre, in: viewSize, maxAngle: .pi)
        } else if focusedPlantID != nil, targetDistance > Self.focusOutDistance {
            focusedPlantID = nil
        } else if let candidate = pinchCandidateID, candidate != focusedPlantID, zoom > 1.05 {
            // Already visiting someone and pinched out on a different
            // flower: move over to that one.
            focusedPlantID = candidate
        }
    }

    func pinchEnded() {
        isPinching = false
        pinchStartDistance = nil
        pinchCandidateID = nil
    }

    // MARK: Frame update

    func tick(_ rawDelta: Float) {
        guard let camera, let island else { return }
        let delta = min(rawDelta, 1.0 / 20.0)
        time += delta

        if autoRotate { targetYaw += delta * 0.15 }

        // The island floats gently up and down.
        island.position.y = sin(time * 0.9) * 0.03

        // Each plant has its own fixed turn so they don't all face the
        // same way, plus a small sway.
        for (id, entity) in plantEntities {
            let turn = plantTurn[id] ?? 0
            let sway = sin(time * 1.4 + turn * 3) * 0.03
            entity.orientation = simd_quatf(angle: turn, axis: [0, 1, 0]) * simd_quatf(angle: sway, axis: [0, 0, 1])
        }

        let ease = 1 - exp(-delta * 7)
        yaw += (targetYaw - yaw) * ease
        pitch += (targetPitch - pitch) * ease
        distance += (targetDistance - distance) * ease

        var goal = island.position(relativeTo: nil) + SIMD3<Float>(0, 0.08, 0)
        if let id = focusedPlantID, let point = focusPoint(for: id) {
            goal = point
        }
        target += (goal - target) * ease

        camera.look(at: target, from: cameraPosition, relativeTo: nil)
    }

    // MARK: Helpers

    private var cameraPosition: SIMD3<Float> {
        let direction = SIMD3<Float>(cos(pitch) * sin(yaw), sin(pitch), cos(pitch) * cos(yaw))
        return target + direction * distance
    }

    private func focusPoint(for id: String) -> SIMD3<Float>? {
        guard let entity = plantEntities[id] else { return nil }
        let height = plantStages[id]?.height ?? 0.2
        return entity.position(relativeTo: nil) + SIMD3<Float>(0, height * 0.65, 0)
    }

    // Finds the plant closest to a point on screen by comparing the
    // direction to each plant with the direction of a ray through that
    // point. No hit testing needed, and it's forgiving if your fingers
    // land slightly off the flower.
    private func plantID(at location: CGPoint, in size: CGSize, maxAngle: Float) -> String? {
        guard size.width > 0, size.height > 0, !plantEntities.isEmpty else { return nil }

        let eye = cameraPosition
        let forward = simd_normalize(target - eye)
        let right = simd_normalize(simd_cross(forward, SIMD3<Float>(0, 1, 0)))
        let up = simd_cross(right, forward)
        let tanHalf = tan(Self.fieldOfView * .pi / 360)
        let aspect = Float(size.width / size.height)
        let x = Float(location.x / size.width) * 2 - 1
        let y = 1 - Float(location.y / size.height) * 2
        let ray = simd_normalize(forward + right * (x * tanHalf * aspect) + up * (y * tanHalf))

        var best: (id: String, angle: Float)?
        for id in plantEntities.keys {
            guard let point = focusPoint(for: id) else { continue }
            let angle = acos(min(max(simd_dot(ray, simd_normalize(point - eye)), -1), 1))
            if angle <= maxAngle, angle < (best?.angle ?? .infinity) {
                best = (id, angle)
            }
        }
        return best?.id
    }

    private func plantID(forEntity entity: Entity) -> String? {
        var current: Entity? = entity
        while let candidate = current {
            if let id = candidate.components[PlantIdentifierComponent.self]?.plantID {
                return id
            }
            current = candidate.parent
        }
        return nil
    }
}

private struct PlantIdentifierComponent: Component {
    let plantID: String
}

// MARK: - Models

// All garden geometry, built from a few shared primitive meshes that
// are scaled into petals, leaves, stems and island layers. Colours come
// from the Bloom palette.
@MainActor
private enum GardenModels {

    // MARK: Colours

    private static func hex(_ value: UInt32) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    private static func mix(_ a: UIColor, _ b: UIColor, _ amount: CGFloat) -> UIColor {
        var (r1, g1, b1, a1): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        var (r2, g2, b2, a2): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        a.getRed(&r1, green: &g1, blue: &b1, alpha: &a1)
        b.getRed(&r2, green: &g2, blue: &b2, alpha: &a2)
        return UIColor(
            red: r1 + (r2 - r1) * amount,
            green: g1 + (g2 - g1) * amount,
            blue: b1 + (b2 - b1) * amount,
            alpha: 1
        )
    }

    private static let grass = hex(0x6E9A45)
    private static let soil = hex(0x9E7C63)
    private static let soilDark = hex(0x7E634F)
    private static let soilDeep = hex(0x5F4A3B)
    private static let rock = hex(0xB9AFA4)
    private static let stemGreen = hex(0x588236)
    private static let leafGreen = hex(0x6E9A45)
    private static let tiredGreen = hex(0x8F8D4E)
    private static let deadBrown = hex(0x7E634F)
    private static let deadPetal = hex(0xA89380)
    private static let mustard = hex(0xEEA316)

    // Each person's flower gets one of the brand colours, picked from
    // their id so it never changes between launches.
    private static let petalColours = [hex(0xD87A70), hex(0xC92E3E), hex(0xEEA316), hex(0x326B96)]

    private static func colours(for plantID: String) -> (petal: UIColor, centre: UIColor) {
        let index = Int(hash(plantID) % UInt64(petalColours.count))
        let petal = petalColours[index]
        // A mustard flower gets a brown centre, like a sunflower.
        return (petal, index == 2 ? soilDeep : mustard)
    }

    private static func material(_ colour: UIColor) -> SimpleMaterial {
        SimpleMaterial(color: colour, roughness: 0.85, isMetallic: false)
    }

    // MARK: Shared meshes

    private static let sphere = MeshResource.generateSphere(radius: 0.5)
    private static let cylinder = MeshResource.generateCylinder(height: 1, radius: 0.5)

    // A squashed sphere. Petals, leaves, rocks and mounds are all blobs.
    private static func blob(_ size: SIMD3<Float>, _ colour: UIColor) -> ModelEntity {
        let entity = ModelEntity(mesh: sphere, materials: [material(colour)])
        entity.scale = size
        return entity
    }

    // A stem segment that grows up from its own origin. Returns the
    // segment and an empty entity at its tip to hang the next part on.
    private static func stem(length: Float, radius: Float, colour: UIColor) -> (base: Entity, tip: Entity) {
        let base = Entity()
        let rod = ModelEntity(mesh: cylinder, materials: [material(colour)])
        rod.scale = [radius * 2, length, radius * 2]
        rod.position.y = length / 2
        base.addChild(rod)
        let tip = Entity()
        tip.position.y = length
        base.addChild(tip)
        return (base, tip)
    }

    private static func pivot(z angle: Float, yaw: Float = 0) -> Entity {
        let entity = Entity()
        entity.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: angle, axis: [0, 0, 1])
        return entity
    }

    // A leaf sticking out from a stem. Positive `lift` points it up,
    // negative makes it droop.
    private static func leaf(length: Float, lift: Float, yaw: Float, colour: UIColor) -> Entity {
        let spin = Entity()
        spin.orientation = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let tilt = Entity()
        tilt.orientation = simd_quatf(angle: -lift, axis: [1, 0, 0])
        let shape = blob([length * 0.45, length * 0.08, length], colour)
        shape.position.z = length * 0.5
        tilt.addChild(shape)
        spin.addChild(tilt)
        return spin
    }

    // A ring of petals around a centre. `open` tilts the petals up into
    // a cup; a negative value makes them hang down.
    private static func flowerHead(petals count: Int, length: Float, open: Float, petal: UIColor, centre: UIColor) -> Entity {
        let head = Entity()
        for index in 0..<count {
            let spin = Entity()
            spin.orientation = simd_quatf(angle: Float(index) / Float(count) * 2 * .pi, axis: [0, 1, 0])
            let tilt = Entity()
            tilt.orientation = simd_quatf(angle: -open, axis: [1, 0, 0])
            let shape = blob([length * 0.55, length * 0.14, length], petal)
            shape.position.z = length * 0.45
            tilt.addChild(shape)
            spin.addChild(tilt)
            head.addChild(spin)
        }
        let middle = blob([length * 0.6, length * 0.38, length * 0.6], centre)
        middle.position.y = length * 0.06
        head.addChild(middle)
        return head
    }

    // A petal or leaf lying flat on the grass.
    private static func fallen(_ size: SIMD3<Float>, _ colour: UIColor, at position: SIMD3<Float>, turn: Float) -> Entity {
        let piece = blob(size, colour)
        piece.position = position
        piece.orientation = simd_quatf(angle: turn, axis: [0, 1, 0])
        return piece
    }

    // MARK: Island

    static func makeIsland() -> Entity {
        let island = Entity()

        // Grass top. Its upper surface sits at y = 0.
        let top = ModelEntity(
            mesh: .generateBox(size: [1.6, 0.1, 1.6], cornerRadius: 0.04),
            materials: [material(grass)]
        )
        top.position.y = -0.05
        island.addChild(top)

        // Soil layers that get smaller towards the bottom, each turned
        // slightly so it looks hand made rather than perfect.
        let layers: [(size: Float, height: Float, y: Float, turn: Float, colour: UIColor)] = [
            (1.56, 0.22, -0.21, 0.00, soil),
            (1.24, 0.20, -0.42, 0.08, soilDark),
            (0.86, 0.18, -0.61, -0.12, soilDeep),
            (0.44, 0.16, -0.78, 0.20, soilDeep),
        ]
        for layer in layers {
            let block = ModelEntity(
                mesh: .generateBox(size: [layer.size, layer.height, layer.size], cornerRadius: 0.05),
                materials: [material(layer.colour)]
            )
            block.position.y = layer.y
            block.orientation = simd_quatf(angle: layer.turn, axis: [0, 1, 0])
            island.addChild(block)
        }

        // A couple of rocks near the corners.
        let rockA = blob([0.13, 0.08, 0.11], rock)
        rockA.position = [0.64, 0.02, -0.62]
        island.addChild(rockA)
        let rockB = blob([0.08, 0.05, 0.09], rock)
        rockB.position = [-0.68, 0.015, 0.6]
        island.addChild(rockB)
        let rockC = blob([0.06, 0.04, 0.05], rock)
        rockC.position = [-0.56, 0.012, 0.66]
        island.addChild(rockC)

        return island
    }

    // MARK: Layout

    // Plants sit on a grid that fits the island, in sorted-id order so
    // nobody moves between launches, with a small fixed nudge each so
    // it doesn't look like a spreadsheet.
    static func layout(ids: [String]) -> [String: SIMD3<Float>] {
        let count = ids.count
        guard count > 0 else { return [:] }
        guard count > 1 else { return [ids[0]: .zero] }

        let columns = Int(ceil(sqrt(Double(count))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let spacing = min(0.42, 1.25 / Float(max(columns, rows)))
        var result: [String: SIMD3<Float>] = [:]

        for (index, id) in ids.enumerated() {
            let row = index / columns
            let column = index % columns
            let inThisRow = row == rows - 1 ? count - row * columns : columns
            let x = (Float(column) - Float(inThisRow - 1) / 2) * spacing
            let z = (Float(row) - Float(rows - 1) / 2) * spacing
            let nudgeX = (unit(id, salt: 1) - 0.5) * spacing * 0.25
            let nudgeZ = (unit(id, salt: 2) - 0.5) * spacing * 0.25
            result[id] = [x + nudgeX, 0, z + nudgeZ]
        }
        return result
    }

    // MARK: Plants

    static func makePlant(stage: GardenStage, plantID: String) -> Entity {
        let container = Entity()
        let (petal, centre) = colours(for: plantID)

        // A small patch of soil under every plant so it looks planted.
        let patch = ModelEntity(mesh: cylinder, materials: [material(soilDark)])
        patch.scale = [0.13, 0.008, 0.13]
        patch.position.y = 0.004
        container.addChild(patch)

        switch stage {
        case .empty:
            let mound = blob([0.15, 0.06, 0.15], soilDark)
            mound.position.y = 0.01
            container.addChild(mound)
            let pebble = blob([0.025, 0.018, 0.022], rock)
            pebble.position = [0.05, 0.03, 0.02]
            container.addChild(pebble)

        case .sprout:
            let shoot = stem(length: 0.08, radius: 0.007, colour: stemGreen)
            container.addChild(shoot.base)
            shoot.tip.addChild(leaf(length: 0.055, lift: 0.6, yaw: 0, colour: leafGreen))
            shoot.tip.addChild(leaf(length: 0.055, lift: 0.6, yaw: .pi, colour: leafGreen))

        case .bud:
            let main = stem(length: 0.2, radius: 0.009, colour: stemGreen)
            container.addChild(main.base)
            let leafJoint = Entity()
            leafJoint.position.y = 0.07
            main.base.addChild(leafJoint)
            leafJoint.addChild(leaf(length: 0.075, lift: 0.4, yaw: 0.3, colour: leafGreen))
            leafJoint.addChild(leaf(length: 0.07, lift: 0.4, yaw: .pi + 0.3, colour: leafGreen))
            let sepal = blob([0.04, 0.045, 0.04], stemGreen)
            sepal.position.y = 0.01
            main.tip.addChild(sepal)
            let bud = blob([0.045, 0.085, 0.045], petal)
            bud.position.y = 0.05
            main.tip.addChild(bud)

        case .flower:
            let main = stem(length: 0.3, radius: 0.01, colour: stemGreen)
            container.addChild(main.base)
            for (height, yaw) in [(Float(0.09), Float(0.3)), (0.17, Float.pi + 0.5)] {
                let joint = Entity()
                joint.position.y = height
                main.base.addChild(joint)
                joint.addChild(leaf(length: 0.09, lift: 0.35, yaw: yaw, colour: leafGreen))
            }
            main.tip.addChild(flowerHead(petals: 6, length: 0.075, open: 0.35, petal: petal, centre: centre))

        case .fullBloom:
            let main = stem(length: 0.36, radius: 0.011, colour: stemGreen)
            container.addChild(main.base)
            for (height, yaw) in [(Float(0.07), Float(0)), (0.13, 2.1), (0.2, 4.2)] {
                let joint = Entity()
                joint.position.y = height
                main.base.addChild(joint)
                joint.addChild(leaf(length: 0.1, lift: 0.3, yaw: yaw, colour: leafGreen))
            }
            main.tip.addChild(flowerHead(petals: 8, length: 0.09, open: 0.3, petal: petal, centre: centre))

            // Two smaller flowers branching off the main stem.
            for (height, lean, yaw) in [(Float(0.15), Float(0.6), Float(0.4)), (0.22, -0.55, 1.2)] {
                let joint = Entity()
                joint.position.y = height
                main.base.addChild(joint)
                let bend = pivot(z: lean, yaw: yaw)
                joint.addChild(bend)
                let branch = stem(length: 0.14, radius: 0.007, colour: stemGreen)
                bend.addChild(branch.base)
                let upright = pivot(z: -lean * 0.7)
                branch.tip.addChild(upright)
                upright.addChild(flowerHead(petals: 6, length: 0.055, open: 0.45, petal: petal, centre: centre))
            }

        case .wilting:
            let faded = mix(petal, soil, 0.55)
            let lower = stem(length: 0.16, radius: 0.009, colour: tiredGreen)
            container.addChild(lower.base)
            let leafJoint = Entity()
            leafJoint.position.y = 0.06
            lower.base.addChild(leafJoint)
            leafJoint.addChild(leaf(length: 0.08, lift: -0.5, yaw: 0.4, colour: tiredGreen))
            leafJoint.addChild(leaf(length: 0.07, lift: -0.6, yaw: .pi + 0.2, colour: tiredGreen))
            // The top of the stem bends over so the head hangs down.
            let bend = pivot(z: 1.0)
            lower.tip.addChild(bend)
            let upper = stem(length: 0.1, radius: 0.008, colour: tiredGreen)
            bend.addChild(upper.base)
            let droop = pivot(z: 0.6)
            upper.tip.addChild(droop)
            droop.addChild(flowerHead(petals: 5, length: 0.06, open: -0.5, petal: faded, centre: mix(centre, soil, 0.4)))
            container.addChild(fallen([0.035, 0.008, 0.06], faded, at: [-0.06, 0.006, 0.05], turn: 0.8))

        case .withered:
            let lower = stem(length: 0.1, radius: 0.008, colour: deadBrown)
            container.addChild(lower.base)
            // Snapped over near the top.
            let snap = pivot(z: 1.7)
            lower.tip.addChild(snap)
            let upper = stem(length: 0.08, radius: 0.006, colour: deadBrown)
            snap.addChild(upper.base)
            let knob = blob([0.025, 0.02, 0.025], deadBrown)
            upper.tip.addChild(knob)
            // Petals and a leaf that have dropped onto the grass.
            container.addChild(fallen([0.035, 0.007, 0.06], deadPetal, at: [0.07, 0.005, 0.03], turn: 0.3))
            container.addChild(fallen([0.03, 0.007, 0.055], deadPetal, at: [-0.05, 0.005, 0.07], turn: 2.0))
            container.addChild(fallen([0.032, 0.007, 0.05], deadPetal, at: [0.02, 0.005, -0.08], turn: 4.1))
            container.addChild(fallen([0.04, 0.008, 0.08], deadBrown, at: [-0.08, 0.006, -0.03], turn: 1.2))
        }

        container.components.set(PlantIdentifierComponent(plantID: plantID))
        container.components.set(InputTargetComponent())
        let height = max(stage.height, 0.1)
        let tapShape = ShapeResource.generateBox(size: [0.22, height + 0.06, 0.22])
            .offsetBy(translation: [0, height / 2, 0])
        container.components.set(CollisionComponent(shapes: [tapShape]))

        return container
    }

    // MARK: Stable randomness

    // String.hashValue changes every launch, so use a simple fixed
    // hash instead. Same id, same colour and nudge, every time.
    private static func hash(_ string: String) -> UInt64 {
        var value: UInt64 = 5381
        for byte in string.utf8 {
            value = (value &* 33) &+ UInt64(byte)
        }
        return value
    }

    // A number from 0 to 1 that is always the same for an id and salt.
    static func unit(_ string: String, salt: UInt64) -> Float {
        let mixed = (hash(string) &+ salt &* 0x9E3779B97F4A7C15) &* 0xBF58476D1CE4E5B9
        return Float((mixed >> 40) & 0xFFFF) / Float(0xFFFF)
    }
}

#if DEBUG
private let gardenPreviewPlants: [GardenPlant] = [
    GardenPlant(id: "preview-you", username: "You", currentStreak: 21, plantState: .blooming, isMe: true),
    GardenPlant(id: "preview-flower", username: "priya", currentStreak: 9, plantState: .blooming, displayName: "Priya"),
    GardenPlant(id: "preview-bud", username: "sam", currentStreak: 4, plantState: .blooming),
    GardenPlant(id: "preview-sprout", username: "lee", currentStreak: 1, plantState: .blooming),
    GardenPlant(id: "preview-wilting", username: "tom", currentStreak: 0, plantState: .wilting),
    GardenPlant(id: "preview-dead", username: "mei", currentStreak: 0, plantState: .dead),
    GardenPlant(id: "preview-none", username: "jordan", currentStreak: 0, plantState: nil),
]

#Preview("Card") {
    GardenRealityView(plants: gardenPreviewPlants)
        .frame(width: 320, height: 320)
        .background(Theme.Palette.greenTint)
}

#Preview("Full Screen") {
    FullScreenGardenView(plants: gardenPreviewPlants)
}

#Preview("Full Screen, Dark") {
    FullScreenGardenView(plants: gardenPreviewPlants)
        .preferredColorScheme(.dark)
}
#endif
