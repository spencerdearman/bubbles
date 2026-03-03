//
//  BubbleGestures.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import RealityKit
import SwiftUI

/// Provides specialized gestures for interacting with bubbles in the ImmersiveView.
public struct BubbleGestures {

  /// A spatial tap gesture that applies a random physical impulse to the targeted bubble.
  public static func tapGesture(
    targetedTo predicate: QueryPredicate<Entity>
  ) -> some Gesture {
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
  }

  /// A long-press gesture that initiates the popping animation via a shader parameter and removes the entity when finished.
  public static func popGesture(
    targetedTo predicate: QueryPredicate<Entity>,
    timer: Binding<Timer?>
  ) -> some Gesture {
    LongPressGesture(minimumDuration: 0.5)
      .targetedToEntity(where: predicate)
      .onEnded { value in
        let entity = value.entity
        guard
          var material = entity.components[ModelComponent.self]?.materials.first
            as? ShaderGraphMaterial
        else { return }

        // Animate the pop property to go from 0 -> 1
        let frameRate: TimeInterval = 1.0 / 60.0  // 60 fps
        let duration: TimeInterval = 0.25  // bubble pops in 0.25 seconds
        let targetValue: Float = 1
        let totalFrames: Int = Int(duration / frameRate)
        var currentFrame = 0
        var popValue: Float = 0

        // Create the timer
        timer.wrappedValue?.invalidate()
        timer.wrappedValue = Timer.scheduledTimer(withTimeInterval: frameRate, repeats: true) {
          localTimer in
          currentFrame += 1
          let progress = Float(currentFrame) / Float(totalFrames)
          popValue = progress * targetValue

          do {
            try material.setParameter(name: "Pop", value: .float(popValue))
            entity.components[ModelComponent.self]?.materials = [material]
          } catch {
            print("Error updating shader: \(error.localizedDescription)")
          }

          // Once popped, invalidate timer and remove entity
          if currentFrame >= totalFrames {
            localTimer.invalidate()
            entity.removeFromParent()
          }
        }
      }
  }
}
