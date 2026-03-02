//
//  BubblesApp.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import SwiftUI
import RealityKit // Required for component/system registration

struct BubbleComponent: Component {
    var spawnTime: Date = Date()
}

// Collision Groups
enum BubbleCollisionGroup {
    static let bubble = CollisionGroup(rawValue: 1 << 0)
    static let hand = CollisionGroup(rawValue: 1 << 1)
    static let scene = CollisionGroup(rawValue: 1 << 2)
}
struct PopComponent: Component {
    var progress: Float = 0
    var isPopping: Bool = false
}
// No magnetic or sword components needed

class BubblePhysicsSystem: System {
    private static let query = EntityQuery(where: .has(BubbleComponent.self) && .has(PhysicsMotionComponent.self))
    
    private var totalTime: Float = 0
    
    required init(scene: RealityKit.Scene) { }
    
    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        totalTime += dt
        
        // --- 2. Update Bubbles ---
        for entity in context.scene.performQuery(Self.query) {
            // 1. Handle Popping Logic
            if var pop = entity.components[PopComponent.self] {
                if pop.isPopping {
                    pop.progress += dt * 4.0 // Pop in 0.25s
                    
                    if var material = entity.components[ModelComponent.self]?.materials.first as? ShaderGraphMaterial {
                        do {
                            try material.setParameter(name: "Pop", value: .float(pop.progress))
                            entity.components[ModelComponent.self]?.materials = [material]
                        } catch {
                            print("Error setting shader parameter: \(error)")
                        }
                    }
                    
                    if pop.progress >= 1.0 {
                        entity.removeFromParent()
                        continue
                    }
                    entity.components.set(pop)
                    
                    // IF POPPING, DO NOT APPLY PHYSICS
                    if var motion = entity.components[PhysicsMotionComponent.self] {
                        motion.linearVelocity = .zero
                        entity.components.set(motion)
                    }
                    continue // Skip physics if popping
                }
            } else {
                entity.components.set(PopComponent())
            }

            // Standard drift logic (batting is handled by kinematic hand joints automatically)

            // 3. Physics & Drift
            if var motion = entity.components[PhysicsMotionComponent.self] {
                let pos = entity.position(relativeTo: nil)
                
                // Pop if hits the floor (y < 0.05)
                if pos.y < 0.05 {
                    var pop = entity.components[PopComponent.self] ?? PopComponent()
                    pop.isPopping = true
                    entity.components.set(pop)
                    motion.linearVelocity = .zero
                    entity.components.set(motion)
                    continue
                }

                // Organic, smooth independent paths. NO GLOBAL WIND/CLUMPING.
                // 0. LIFESPAN: Pop after ~30 seconds to prevent clutter.
                let age = Float(Date().timeIntervalSince(entity.components[BubbleComponent.self]?.spawnTime ?? Date()))
                if age > 30.0 {
                    var pop = entity.components[PopComponent.self] ?? PopComponent()
                    pop.isPopping = true
                    entity.components.set(pop)
                    continue
                }

                // 1. NEUTRAL BUOYANCY: Slight oscillation (~weightless) instead of constant lift. 
                // This prevents them from all ending up on the ceiling.
                let buoyancyY = sin(totalTime * 0.5 + Float(entity.id.hashValue % 100)) * 0.005
                let buoyancy = SIMD3<Float>(0, buoyancyY, 0)
                
                // 2. LOCAL TURBULENCE: Unique, position-independent flutter for each bubble.
                let id = Float(entity.id.hashValue % 1000)
                let noiseX = sin(totalTime * 1.5 + id) * 0.06
                let noiseY = cos(totalTime * 1.2 + id * 0.7) * 0.05
                let noiseZ = sin(totalTime * 1.8 + id * 0.3) * 0.06
                let turbulence = SIMD3<Float>(noiseX, noiseY, noiseZ)
                
                // 3. QUADRATIC DRAG: naturally smoothens movement and caps speed.
                let velocity = motion.linearVelocity
                let speed = length(velocity)
                let dragCoefficient: Float = 0.95 // Higher drag for more control
                let dragForce = speed > 0.001 ? -dragCoefficient * speed * velocity : .zero
                
                // 4. SUM FORCES
                let totalForce = buoyancy + turbulence + dragForce
                
                // Apply force to velocity
                motion.linearVelocity += totalForce * dt
                
                entity.components.set(motion)
            }
        }
    }
}

@main
struct BubblesApp: App {
    @State private var appModel = AppModel()
    
    init() {
        BubbleComponent.registerComponent()
        PopComponent.registerComponent()
        BubblePhysicsSystem.registerSystem()
    }
    
    // 2. Explicitly specify SwiftUI.Scene to resolve ambiguity
    var body: some SwiftUI.Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
        }
        .defaultSize(width: 500, height: 350)
        
        ImmersiveSpace(id: appModel.immersiveSpaceID) {
            ImmersiveView()
                .environment(appModel)
                .onAppear {
                    appModel.immersiveSpaceState = .open
                }
                .onDisappear {
                    appModel.immersiveSpaceState = .closed
                }
        }
        .immersionStyle(selection: Binding(
            get: {
                switch appModel.currentImmersionStyleInt {
                case 1: return .progressive
                case 2: return .full
                default: return .mixed
                }
            },
            set: { _ in }
        ), in: .mixed, .progressive, .full)
    }
}
