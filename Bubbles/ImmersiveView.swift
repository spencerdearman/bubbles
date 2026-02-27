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
    @State private var rootEntity = Entity()
    
    func createInvisibleBoundingBox(width: Float, height: Float, depth: Float) -> Entity {
        let box = Entity()
        // high restitution so bubbles bounce nicely off the walls
        let material = PhysicsMaterialResource.generate(friction: 0.1, restitution: 0.95)
        
        let createWall = { (w: Float, h: Float, d: Float, pos: SIMD3<Float>) -> Entity in
            let wall = Entity()
            let shape = ShapeResource.generateBox(width: w, height: h, depth: d)
            wall.components.set(CollisionComponent(shapes: [shape]))
            var physics = PhysicsBodyComponent(mode: .static)
            physics.material = material
            wall.components.set(physics)
            wall.position = pos
            return wall
        }
        
        let t: Float = 0.5 // Wall thickness
        let halfW = width / 2
        let halfH = height / 2
        let halfD = depth / 2
        
        // Floor & Ceiling
        box.addChild(createWall(width, t, depth, [0, -halfH - t/2, 0]))
        box.addChild(createWall(width, t, depth, [0, halfH + t/2, 0]))
        
        // Left & Right
        box.addChild(createWall(t, height, depth, [-halfW - t/2, 0, 0]))
        box.addChild(createWall(t, height, depth, [halfW + t/2, 0, 0]))
        
        // Front & Back
        box.addChild(createWall(width, height, t, [0, 0, -halfD - t/2]))
        box.addChild(createWall(width, height, t, [0, 0, halfD + t/2]))
        
        return box
    }
    
    var body: some View {
        RealityView { content in
            // Add root entity for hand tracking joints
            content.add(rootEntity)
            
            // Add the initial RealityKit content
            if let immersiveContentEntity = try? await Entity(named: "BubbleScene", in: realityKitContentBundle) {
                rootEntity.addChild(immersiveContentEntity)
                
                // Add bounding box
                let boundingBox = createInvisibleBoundingBox(width: 5.0, height: 2.0, depth: 5.0)
                boundingBox.position = [0, 1.0, -0.5] // Rest on floor (y=0) up to y=2.0
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
                        
                        // Randomize starting position out of the straight line
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
            }
        }
        .task {
            // Run Hand Tracking to map physical spheres to joints
            do {
                try await session.run([handTracking])
                for await update in handTracking.anchorUpdates {
                    let anchor = update.anchor
                    guard anchor.isTracked, let skeleton = anchor.handSkeleton else { continue }
                    
                    for joint in skeleton.allJoints {
                        let jointName = "\(anchor.chirality)-\(joint.name)"
                        var jointEntity = rootEntity.findEntity(named: jointName)
                        
                        if jointEntity == nil {
                            jointEntity = Entity()
                            jointEntity?.name = jointName
                            
                            // Give the joint a physical body so it can interact with bubbles
                            let shape = ShapeResource.generateSphere(radius: 0.02)
                            jointEntity?.components.set(CollisionComponent(shapes: [shape]))
                            
                            var physics = PhysicsBodyComponent(mode: .kinematic)
                            physics.material = .generate(friction: 0.5, restitution: 0.8)
                            jointEntity?.components.set(physics)
                            
                            rootEntity.addChild(jointEntity!)
                        }
                        
                        let jointTransform = matrix_multiply(anchor.originFromAnchorTransform, joint.anchorFromJointTransform)
                        jointEntity?.setTransformMatrix(jointTransform, relativeTo: nil)
                    }
                }
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
    
    // Helper to spawn a new bubble by duplicating an existing one
    func spawnNewBubble() {
        func findBubble(in entity: Entity) -> Entity? {
            if entity.name.contains("Bubble") && entity.components.has(CollisionComponent.self) {
                return entity
            }
            for child in entity.children {
                if let found = findBubble(in: child) {
                    return found
                }
            }
            return nil
        }

        if let bubbleToClone = findBubble(in: rootEntity) {
            let newBubble = bubbleToClone.clone(recursive: true)
            
            // Randomize position within the box
            newBubble.position = SIMD3<Float>(
                Float.random(in: -0.5...0.5),
                Float.random(in: 0.5...1.5), // spawn in air
                Float.random(in: -0.8...(-0.2)) // slightly in front
            )
            
            // Give it some initial random velocity
            if var motion = newBubble.components[PhysicsMotionComponent.self] {
                motion.linearVelocity = [
                    Float.random(in: -0.5...0.5),
                    Float.random(in: -0.5...0.5),
                    Float.random(in: -0.5...0.5)
                ]
                newBubble.components.set(motion)
            }
            
            // Add back to the scene
            rootEntity.addChild(newBubble)
        } else {
            print("Could not find a bubble to clone.")
        }
    }
}

#Preview(immersionStyle: .mixed) {
    ImmersiveView()
        .environment(AppModel())
}
