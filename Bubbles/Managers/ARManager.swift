//
//  ARManager.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import ARKit
import Foundation
import RealityKit

/// Manages ARKit session lifecycle and tracking providers.
@MainActor
@Observable
public class ARManager {
  public let session = ARKitSession()
  public let handTracking = HandTrackingProvider()
  public let sceneReconstruction = SceneReconstructionProvider()
  public let worldTracking = WorldTrackingProvider()

  public var meshEntities: [UUID: Entity] = [:]

  public init() {}

  /// Starts the ARKit session with necessary providers.
  public func startSession() async {
    do {
      try await session.run([handTracking, sceneReconstruction, worldTracking])
    } catch {
      print("Error starting ARKit session: \(error)")
    }
  }

  /// Generates a collision mesh from a MeshAnchor for environment interaction.
  public func generateMeshEntity(from anchor: MeshAnchor) async throws -> Entity {
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
