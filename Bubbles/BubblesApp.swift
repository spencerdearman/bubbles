//
//  BubblesApp.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import SwiftUI
import RealityKit // Required for component/system registration

// MARK: - Anti-Gravity System
struct BubbleComponent: Component { }

class BubblePhysicsSystem: System {
    private static let query = EntityQuery(where: .has(BubbleComponent.self) && .has(PhysicsMotionComponent.self))
    
    required init(scene: RealityKit.Scene) { }
    
    func update(context: SceneUpdateContext) {
        let dt = Float(context.deltaTime)
        
        for entity in context.scene.performQuery(Self.query) {
            if var motion = entity.components[PhysicsMotionComponent.self] {
                // Apply a continuous random drift force so they don't get stuck and stay in motion
                let driftForce = SIMD3<Float>(
                    Float.random(in: -0.1...0.1),
                    Float.random(in: -0.1...0.1),
                    Float.random(in: -0.1...0.1)
                )
                
                // Nudge bubbles away from walls if they get too close (assuming box is center at [0,1,-0.5] with size 5x2x5)
                let pos = entity.position(relativeTo: nil)
                var antiStickForce = SIMD3<Float>(0, 0, 0)
                let wallPadding: Float = 0.8
                
                // X walls are at -2.5 and +2.5
                if pos.x < (-2.5 + wallPadding) { antiStickForce.x += 0.2 }
                if pos.x > (2.5 - wallPadding) { antiStickForce.x -= 0.2 }
                
                // Y walls are at 0 and 2.0
                if pos.y < (0.0 + wallPadding) { antiStickForce.y += 0.2 } // Floor is 0
                if pos.y > (2.0 - wallPadding) { antiStickForce.y -= 0.2 } // Ceiling is 2
                
                // Z walls are at -3.0 and +2.0 (since center is -0.5 and half-depth is 2.5)
                if pos.z < (-3.0 + wallPadding) { antiStickForce.z += 0.2 }
                if pos.z > (2.0 - wallPadding) { antiStickForce.z -= 0.2 }
                
                motion.linearVelocity += (driftForce + antiStickForce) * dt
                
                // Cap maximum velocity so they don't go crazy
                let maxSpeed: Float = 0.5
                let currentSpeed = length(motion.linearVelocity)
                if currentSpeed > maxSpeed {
                    motion.linearVelocity = normalize(motion.linearVelocity) * maxSpeed
                }
                
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
