//
//  ImmersiveView.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import SwiftUI
import RealityKit
import RealityKitContent
import ARKit

struct ImmersiveView: View {
    @Environment(AppModel.self) var appModel
    
    @State var predicate: QueryPredicate<Entity> = QueryPredicate<Entity>.has(ModelComponent.self)
    @State private var timer: Timer?
    
    @State private var session = ARKitSession()
    @State private var handTracking = HandTrackingProvider()
    @State private var sceneReconstruction = SceneReconstructionProvider()
    @State private var worldTracking = WorldTrackingProvider()
    
    @State private var meshEntities = [UUID: Entity]()
    @State private var rootEntity = Entity()
    @State private var bubbleTemplate: Entity?
    @State private var lastBlowTime: Date = .distantPast
    
    @State private var subscription: EventSubscription?
    
    func createInvisibleBoundingBox() -> Entity {
        // Return thin floor only, or nothing if scene reconstruction is enough
        return Entity()
    }
    
    var body: some View {
        RealityView { content in
            // Add root entity for hand tracking joints
            content.add(rootEntity)
            
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "BubbleScene", in: realityKitContentBundle) {
                rootEntity.addChild(immersiveContentEntity)
                
                // Add bounding box (now empty or minimal)
                let boundingBox = createInvisibleBoundingBox()
                rootEntity.addChild(boundingBox)
                
                // Add physics to bubbles
                func setupPhysics(for entity: Entity) {
                    if entity.name.contains("Bubble") && entity.components.has(CollisionComponent.self) {
                        var physicsBody = PhysicsBodyComponent(mode: .dynamic)
                        let material = PhysicsMaterialResource.generate(friction: 0.1, restitution: 0.95)
                        physicsBody.material = material
                        physicsBody.massProperties.mass = 0.05
                        // Built-in antigravity:
                        physicsBody.isAffectedByGravity = false
                        physicsBody.linearDamping = 0.1 // Lower damping so they drift better
                        physicsBody.angularDamping = 0.5
                        entity.components.set(physicsBody)
                        
                        // Tag for the custom continuous motion system
                        entity.components.set(BubbleComponent())
                        entity.components.set(PopComponent())
                        
                        // Set collision filter for the bubble
                        if var col = entity.components[CollisionComponent.self] {
                            col.filter = CollisionFilter(group: BubbleCollisionGroup.bubble, mask: .all)
                            entity.components.set(col)
                        }
                        
                        // Randomize starting position
                        entity.position += SIMD3<Float>(
                            Float.random(in: -0.5...0.5),
                            Float.random(in: -0.5...0.5),
                            Float.random(in: -0.5...0.5)
                        )
                        
                        var motion = PhysicsMotionComponent()
                        motion.linearVelocity = [
                            Float.random(in: -0.2...0.2),
                            Float.random(in: -0.2...0.2),
                            Float.random(in: -0.2...0.2)
                        ]
                        entity.components.set(motion)
                    }
                    for child in entity.children {
                        setupPhysics(for: child)
                    }
                }
                setupPhysics(for: immersiveContentEntity)
                
                // Save a template for cloning later
                func findBubbleTemplate(in entity: Entity) -> Entity? {
                    if entity.name.contains("Bubble") && entity.components.has(CollisionComponent.self) {
                        return entity
                    }
                    for child in entity.children {
                        if let found = findBubbleTemplate(in: child) {
                            return found
                        }
                    }
                    return nil
                }
                
                if let found = findBubbleTemplate(in: immersiveContentEntity) {
                    bubbleTemplate = found.clone(recursive: true)
                }
                
                // Subscribe to collision events
                subscription = content.subscribe(to: CollisionEvents.Began.self) { event in
                    handleCollision(event)
                }
            }
        }
        .task {
            // Run Hand Tracking, Scene Reconstruction, and World Tracking
            do {
                try await session.run([handTracking, sceneReconstruction, worldTracking])
                
                // Handle hand tracking updates
                let handTask = Task {
                    for await update in handTracking.anchorUpdates {
                        let anchor = update.anchor
                        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { continue }
                        
                        for joint in skeleton.allJoints {
                            let jointName = "\(anchor.chirality)-\(joint.name)"
                            var jointEntity = rootEntity.findEntity(named: jointName)
                            
                            if jointEntity == nil {
                                jointEntity = Entity()
                                jointEntity?.name = jointName
                                
                                // Only give "High Value" joints a physical body for "Fluid Batting"
                                // This prevents bubbles getting stuck in knuckles.
                                let highValueJoints: Set<HandSkeleton.JointName> = [
                                    .indexFingerTip, .middleFingerTip, .ringFingerTip, .littleFingerTip, .thumbTip, .wrist
                                ]
                                
                                if highValueJoints.contains(joint.name) {
                                    let shape = ShapeResource.generateSphere(radius: 0.03) // Slightly larger for better batting
                                    var collision = CollisionComponent(shapes: [shape])
                                    collision.filter = CollisionFilter(group: BubbleCollisionGroup.hand, mask: .all)
                                    jointEntity?.components.set(collision)
                                    
                                    var physics = PhysicsBodyComponent(mode: .kinematic)
                                    // Perfect bounciness for fluid batting
                                    physics.material = .generate(friction: 0.0, restitution: 1.0)
                                    jointEntity?.components.set(physics)
                                }
                                
                                rootEntity.addChild(jointEntity!)
                            }
                            
                            let jointTransform = matrix_multiply(anchor.originFromAnchorTransform, joint.anchorFromJointTransform)
                            jointEntity?.setTransformMatrix(jointTransform, relativeTo: nil)
                        }
                        
                        // Check for blowing gesture
                        checkBlowingGesture(anchor: anchor)
                    }
                }
                
                // Handle scene reconstruction updates
                let sceneTask = Task {
                    for await update in sceneReconstruction.anchorUpdates {
                        let meshAnchor = update.anchor
                        
                        switch update.event {
                        case .added, .updated:
                            if let mesh = try? await generateMeshEntity(from: meshAnchor) {
                                if let existing = meshEntities[meshAnchor.id] {
                                    existing.removeFromParent()
                                }
                                rootEntity.addChild(mesh)
                                meshEntities[meshAnchor.id] = mesh
                            }
                        case .removed:
                            meshEntities[meshAnchor.id]?.removeFromParent()
                            meshEntities.removeValue(forKey: meshAnchor.id)
                        }
                    }
                }
                
                // Wait for both tasks (they run indefinitely until the view disappears)
                _ = await [handTask.value, sceneTask.value]
                
            } catch {
                print("Error starting ARKit session: \(error)")
            }
        }
        .gesture(
            SpatialTapGesture()
                .targetedToEntity(where: predicate)
                .onEnded { value in
                    let entity = value.entity
                    
                    if var motion = entity.components[PhysicsMotionComponent.self] {
                        let impulse = SIMD3<Float>(
                            Float.random(in: -0.5...0.5),
                            Float.random(in: 1.0...2.0),
                            Float.random(in: -1.0...(-0.2))
                        )
                        motion.linearVelocity += impulse
                        entity.components.set(motion)
                    }
                }
        )
        .gesture(
            LongPressGesture(minimumDuration: 0.5)
                .targetedToEntity(where: predicate)
                .onEnded { value in
                    let entity = value.entity
                    var material = entity.components[ModelComponent.self]?.materials.first as! ShaderGraphMaterial
                    
                    /// Doing some math to animate the shader.
                    /// Want to animate the pop property to go from 0 --> 1
                    let frameRate: TimeInterval = 1.0 / 60.0 // 60 fps
                    let duration: TimeInterval =  0.25 // bubble pops in 0.25 seconds
                    let targetValue: Float = 1
                    let totalFrames: Int = Int(duration / frameRate)
                    var currentFrame = 0
                    var popValue: Float = 0
                    
                    /// Create the timer
                    timer?.invalidate()
                    timer = Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true, block: { timer in
                        currentFrame += 1
                        let progress = Float(currentFrame) / Float(totalFrames)
                        
                        popValue = progress * targetValue
                        
                        do {
                            try material.setParameter(name: "Pop", value: .float(popValue))
                            entity.components[ModelComponent.self]?.materials = [material]
                        } catch {
                            print(error.localizedDescription)
                        }
                        
                        /// Once the bubble pops, invalidate the timer and remove the bubble view from the parent view (the immersive space).
                        if currentFrame >= totalFrames {
                            timer.invalidate()
                            entity.removeFromParent()
                        }
                    })
                }
        )
        .preferredSurroundingsEffect(.systemDark)
        .onReceive(appModel.spawnBubbleEvent) { _ in
            spawnNewBubble()
        }
    }
    
    func handleCollision(_ event: CollisionEvents.Began) {
        // Hand-to-Bubble collisions are kinetic batting. Popping logic for sword removed.
    }
    
    // Helper to spawn a new bubble at a specific location
    func spawnNewBubble(at position: SIMD3<Float>? = nil, withVelocity velocity: SIMD3<Float>? = nil) {
        if let template = bubbleTemplate {
            let newBubble = template.clone(recursive: true)
            
            // Set spawn time for protection
            var bubbleComp = BubbleComponent()
            bubbleComp.spawnTime = Date()
            newBubble.components.set(bubbleComp)
            
            if let pos = position {
                newBubble.position = pos
            } else {
                // Default random position if none provided
                newBubble.position = SIMD3<Float>(
                    Float.random(in: -0.5...0.5),
                    Float.random(in: 0.5...1.5),
                    Float.random(in: -0.8...(-0.2))
                )
            }
            
            // Reverted bubble scale to default (no explicit scale modifier)
            
            if var motion = newBubble.components[PhysicsMotionComponent.self] {
                if let vel = velocity {
                    motion.linearVelocity = vel
                } else {
                    motion.linearVelocity = [
                        Float.random(in: -0.5...0.5),
                        Float.random(in: -0.5...0.5),
                        Float.random(in: -0.5...0.5)
                    ]
                }
                newBubble.components.set(motion)
            }
            
            rootEntity.addChild(newBubble)
        } else {
            print("Could not find a bubble to clone.")
        }
    }
    
    // Check if the hand is near the mouth and performing an "O" (wand) gesture
    func checkBlowingGesture(anchor: HandAnchor) {
        guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return }
        
        // Get index tip and thumb tip
        let indexTip = skeleton.joint(.indexFingerTip)
        let thumbTip = skeleton.joint(.thumbTip)
        let indexKnuckle = skeleton.joint(.indexFingerIntermediateBase)
        
        guard indexTip.isTracked, thumbTip.isTracked, indexKnuckle.isTracked else { return }
        
        // Convert to world space
        let indexPos = (anchor.originFromAnchorTransform * indexTip.anchorFromJointTransform).columns.3.xyz
        let thumbPos = (anchor.originFromAnchorTransform * thumbTip.anchorFromJointTransform).columns.3.xyz
        let knucklePos = (anchor.originFromAnchorTransform * indexKnuckle.anchorFromJointTransform).columns.3.xyz
        
        // Check for cooldown (allow slightly faster blowing)
        guard abs(lastBlowTime.timeIntervalSinceNow) > 0.3 else { return }
        
        // Check for "O" shape: tips are touching/close, but the knuckle is further away
        let tipsDistance = distance(indexPos, thumbPos)
        let isPinch = tipsDistance < 0.04
        
        // Ensure it's not just a flat pinch by checking if the knuckle forms an arc
        let knuckleToThumbDistance = distance(knucklePos, thumbPos)
        let isOShape = isPinch && knuckleToThumbDistance > 0.03
        
        guard isOShape else { return }
        
        // Get head/device position
        guard let deviceAnchor = worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) else { return }
        let headPos = deviceAnchor.originFromAnchorTransform.columns.3.xyz
        
        // Calculate the center of the "O" (midpoint between index and thumb)
        let wandCenter = (indexPos + thumbPos) / 2.0
        
        // Check if wand (hand) is near mouth (roughly 20cm from head)
        let wandToHeadDistance = distance(wandCenter, headPos)
        guard wandToHeadDistance < 0.20 else { return }
        
        // "Blowing" direction: from head through the center of the wand
        let blowDir = normalize(wandCenter - headPos)
        let blowVelocity = blowDir * 0.6 // Reduced speed of the blow to prevent zipping
        
        // Offset the spawn position slightly forward of the hand so it clears the fingers instantly
        let spawnPos = wandCenter + (blowDir * 0.05)
        
        // Spawn bubble
        spawnNewBubble(at: spawnPos, withVelocity: blowVelocity)
        
        // Update cooldown
        lastBlowTime = Date()
    }
    
    // Bubble Sword removed per user request
    
    // Generate a collision mesh from a MeshAnchor
    func generateMeshEntity(from anchor: MeshAnchor) async throws -> Entity {
        let entity = Entity()
        entity.name = "Mesh-\(anchor.id)"
        
        let shape = try await ShapeResource.generateStaticMesh(from: anchor)
        var collision = CollisionComponent(shapes: [shape])
        // Explicitly set collision group so bubbles bounce off the environment properly
        collision.filter = CollisionFilter(group: BubbleCollisionGroup.scene, mask: .all)
        entity.components.set(collision)
        
        var physicsBody = PhysicsBodyComponent(mode: .static)
        // High restitution (bounciness) and low friction so they glide off walls
        physicsBody.material = .generate(friction: 0.1, restitution: 0.95)
        entity.components.set(physicsBody)
        
        entity.setTransformMatrix(anchor.originFromAnchorTransform, relativeTo: nil)
        
        return entity
    }
}

extension SIMD4<Float> {
    var xyz: SIMD3<Float> {
        SIMD3<Float>(x, y, z)
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
