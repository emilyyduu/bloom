//import SceneKit
//import UIKit
//
//// Builds and updates the placeholder SceneKit scene for the Shared
//// Circle Garden: a static ground plane and camera, with one simple
//// plant per person arranged in a circle. This is the Week 10
//// milestone, geometry is intentionally placeholder-simple, not a
//// modeled garden.
//enum GardenSceneBuilder {
//    private static let radius: CGFloat = 3
//
//    // Where around the circle a given person sits, shared by the 3D
//    // plant nodes and the SwiftUI label overlay so the two line up.
//    static func angle(forIndex index: Int, count: Int) -> Double {
//        guard count > 0 else { return 0 }
//        return (Double(index) / Double(count)) * 2 * .pi - .pi / 2
//    }
//
//    static func makeScene() -> (scene: SCNScene, camera: SCNNode) {
//        let scene = SCNScene()
//        scene.background.contents = UIColor.clear
//
//        let groundGeometry = SCNPlane(width: 14, height: 14)
//        groundGeometry.firstMaterial?.diffuse.contents = UIColor.systemGreen.withAlphaComponent(0.25)
//        groundGeometry.firstMaterial?.isDoubleSided = true
//        let ground = SCNNode(geometry: groundGeometry)
//        ground.eulerAngles.x = -Float.pi / 2
//        scene.rootNode.addChildNode(ground)
//
//        let ambientLight = SCNNode()
//        ambientLight.light = SCNLight()
//        ambientLight.light?.type = .ambient
//        ambientLight.light?.color = UIColor(white: 0.55, alpha: 1)
//        scene.rootNode.addChildNode(ambientLight)
//
//        let sunLight = SCNNode()
//        sunLight.light = SCNLight()
//        sunLight.light?.type = .directional
//        sunLight.light?.intensity = 900
//        sunLight.position = SCNVector3(5, 8, 5)
//        sunLight.look(at: SCNVector3Zero)
//        scene.rootNode.addChildNode(sunLight)
//
//        let cameraNode = SCNNode()
//        cameraNode.camera = SCNCamera()
//        cameraNode.position = SCNVector3(0, 6, 8)
//        cameraNode.look(at: SCNVector3(0, 0.5, 0))
//        scene.rootNode.addChildNode(cameraNode)
//
//        let plantsNode = SCNNode()
//        plantsNode.name = "plants"
//        scene.rootNode.addChildNode(plantsNode)
//
//        return (scene, cameraNode)
//    }
//
//    static func update(scene: SCNScene, with plants: [GardenPlant]) {
//        guard let plantsNode = scene.rootNode.childNode(withName: "plants", recursively: false) else { return }
//        plantsNode.childNodes.forEach { $0.removeFromParentNode() }
//
//        let count = plants.count
//        for (index, plant) in plants.enumerated() {
//            let angle = angle(forIndex: index, count: count)
//            let node = plantNode(for: plant.plantState)
//            node.position = SCNVector3(
//                Float(radius * cos(angle)),
//                0,
//                Float(radius * sin(angle))
//            )
//            plantsNode.addChildNode(node)
//        }
//    }
//
//    private static func plantNode(for state: PlantState?) -> SCNNode {
//        let node = SCNNode()
//
//        switch state {
//        case .blooming:
//            node.addChildNode(stemNode(height: 1.0, color: .systemGreen))
//            let bloom = SCNNode(geometry: SCNSphere(radius: 0.22))
//            bloom.geometry?.firstMaterial?.diffuse.contents = UIColor.systemPink
//            bloom.position = SCNVector3(0, 1.1, 0)
//            node.addChildNode(bloom)
//
//        case .wilting:
//            let stemColor = UIColor(red: 0.62, green: 0.52, blue: 0.22, alpha: 1)
//            node.addChildNode(stemNode(height: 0.55, color: stemColor))
//            let bloom = SCNNode(geometry: SCNSphere(radius: 0.14))
//            bloom.geometry?.firstMaterial?.diffuse.contents = UIColor.systemYellow
//            bloom.position = SCNVector3(0.12, 0.5, 0)
//            bloom.eulerAngles.z = Float.pi / 5
//            node.addChildNode(bloom)
//
//        case .dead:
//            let stubColor = UIColor(red: 0.42, green: 0.37, blue: 0.32, alpha: 1)
//            node.addChildNode(stemNode(height: 0.2, color: stubColor))
//
//        case nil:
//            break // An empty plot: no streak record yet.
//        }
//
//        return node
//    }
//
//    private static func stemNode(height: CGFloat, color: UIColor) -> SCNNode {
//        let stem = SCNCylinder(radius: 0.05, height: height)
//        stem.firstMaterial?.diffuse.contents = color
//        let node = SCNNode(geometry: stem)
//        node.position = SCNVector3(0, Float(height / 2), 0)
//        return node
//    }
//}
