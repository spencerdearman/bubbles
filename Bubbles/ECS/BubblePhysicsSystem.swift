//
//  BubblePhysicsSystem.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import Foundation
import RealityKit

/// Custom system to calculate frame-by-frame forces on bubbles, including neutral buoyancy, turbulence, and drag.
public class BubblePhysicsSystem: System {
  private static let query = EntityQuery(
    where: .has(BubbleComponent.self) && .has(PhysicsMotionComponent.self))

  private var totalTime: Float = 0

  public required init(scene: RealityKit.Scene) {}

  public func update(context: SceneUpdateContext) {
    let dt = Float(context.deltaTime)
    totalTime += dt

    // Update bubbles
    for entity in context.scene.performQuery(Self.query) {
      // Handle Popping Logic
      if var pop = entity.components[PopComponent.self] {
        if pop.isPopping {
          pop.progress += dt * 4.0  // Pop in 0.25s

          if var material = entity.components[ModelComponent.self]?.materials.first
            as? ShaderGraphMaterial
          {
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

          // If the bubbles are popping, don't apply any physics
          if var motion = entity.components[PhysicsMotionComponent.self] {
            motion.linearVelocity = .zero
            entity.components.set(motion)
          }
          continue
        }
      } else {
        entity.components.set(PopComponent())
      }

      // Physics & Drift
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

        // Lifespan: Pop after ~30 seconds to prevent clutter.
        let age = Float(
          Date().timeIntervalSince(entity.components[BubbleComponent.self]?.spawnTime ?? Date()))
        if age > 30.0 {
          var pop = entity.components[PopComponent.self] ?? PopComponent()
          pop.isPopping = true
          entity.components.set(pop)
          continue
        }

        // Neutral buoyancy: Slight oscillation (~weightless) instead of constant lift.
        let buoyancyY = sin(totalTime * 0.5 + Float(entity.id.hashValue % 100)) * 0.005
        let buoyancy = SIMD3<Float>(0, buoyancyY, 0)

        // Local turbulence: Unique, position-independent flutter for each bubble.
        let id = Float(entity.id.hashValue % 1000)
        let noiseX = sin(totalTime * 1.5 + id) * 0.06
        let noiseY = cos(totalTime * 1.2 + id * 0.7) * 0.05
        let noiseZ = sin(totalTime * 1.8 + id * 0.3) * 0.06
        let turbulence = SIMD3<Float>(noiseX, noiseY, noiseZ)

        // Quadratic drag: naturally smoothens movement and caps speed.
        let velocity = motion.linearVelocity
        let speed = length(velocity)
        let dragCoefficient: Float = 0.95  // Higher drag for more control
        let dragForce = speed > 0.001 ? -dragCoefficient * speed * velocity : .zero

        // Sum forces
        let totalForce = buoyancy + turbulence + dragForce

        // Apply force to velocity
        motion.linearVelocity += totalForce * dt

        entity.components.set(motion)
      }
    }
  }
}
