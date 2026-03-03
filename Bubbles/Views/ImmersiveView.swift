//
//  ImmersiveView.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import ARKit
import RealityKit
import RealityKitContent
import SwiftUI

struct ImmersiveView: View {
  @Environment(AppModel.self) var appModel

  @State private var arManager = ARManager()

  @State var predicate: QueryPredicate<Entity> = QueryPredicate<Entity>.has(ModelComponent.self)
  @State private var timer: Timer?

  @State private var rootEntity = Entity()
  @State private var bubbleTemplate: Entity?
  @State private var lastBlowTime: Date = .distantPast

  @State private var subscription: EventSubscription?

  var body: some View {
    RealityView { content in
      // Add root entity for hand tracking joints
      content.add(rootEntity)

      // Add the initial RealityKit content
      if let immersiveContentEntity = try? await Entity(
        named: "BubbleScene", in: realityKitContentBundle)
      {
        rootEntity.addChild(immersiveContentEntity)

        // Add physics to bubbles
        setupPhysics(for: immersiveContentEntity)

        // Save a template for cloning later
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
      // Start the ARKit Session via the Manager
      await arManager.startSession()

      // Run observers in parallel
      await withTaskGroup(of: Void.self) { group in
        group.addTask { await observeHandTracking() }
        group.addTask { await observeSceneReconstruction() }
      }
    }
    .gesture(BubbleGestures.tapGesture(targetedTo: predicate))
    .gesture(BubbleGestures.popGesture(targetedTo: predicate, timer: $timer))
    .preferredSurroundingsEffect(.systemDark)
    .onReceive(appModel.spawnBubbleEvent) { _ in
      spawnNewBubble()
    }
  }

  // MARK: - Hand Tracking

  private func observeHandTracking() async {
    for await update in arManager.handTracking.anchorUpdates {
      let anchor = update.anchor
      guard anchor.isTracked, let skeleton = anchor.handSkeleton else { continue }

      for joint in skeleton.allJoints {
        let jointName = "\(anchor.chirality)-\(joint.name)"
        var jointEntity = rootEntity.findEntity(named: jointName)

        if jointEntity == nil {
          jointEntity = createKinematicHandJoint(named: jointName, joint: joint)
        }

        let jointTransform = matrix_multiply(
          anchor.originFromAnchorTransform, joint.anchorFromJointTransform)
        jointEntity?.setTransformMatrix(jointTransform, relativeTo: nil)
      }

      checkBlowingGesture(anchor: anchor)
    }
  }

  private func createKinematicHandJoint(named name: String, joint: HandSkeleton.Joint) -> Entity? {
    let jointEntity = Entity()
    jointEntity.name = name

    let highValueJoints: Set<HandSkeleton.JointName> = [
      .indexFingerTip, .middleFingerTip, .ringFingerTip, .littleFingerTip, .thumbTip, .wrist,
    ]

    if highValueJoints.contains(joint.name) {
      let shape = ShapeResource.generateSphere(radius: 0.03)
      var collision = CollisionComponent(shapes: [shape])
      collision.filter = CollisionFilter(group: BubbleCollisionGroup.hand, mask: .all)
      jointEntity.components.set(collision)

      var physics = PhysicsBodyComponent(mode: .kinematic)
      physics.material = .generate(friction: 0.0, restitution: 1.0)
      jointEntity.components.set(physics)
    }

    rootEntity.addChild(jointEntity)
    return jointEntity
  }

  // MARK: - Scene Reconstruction

  private func observeSceneReconstruction() async {
    for await update in arManager.sceneReconstruction.anchorUpdates {
      let meshAnchor = update.anchor

      switch update.event {
      case .added, .updated:
        if let mesh = try? await arManager.generateMeshEntity(from: meshAnchor) {
          if let existing = arManager.meshEntities[meshAnchor.id] {
            existing.removeFromParent()
          }
          rootEntity.addChild(mesh)
          arManager.meshEntities[meshAnchor.id] = mesh
        }
      case .removed:
        arManager.meshEntities[meshAnchor.id]?.removeFromParent()
        arManager.meshEntities.removeValue(forKey: meshAnchor.id)
      }
    }
  }

  // MARK: - Logic & Setup

  func setupPhysics(for entity: Entity) {
    if entity.name.contains("Bubble") && entity.components.has(CollisionComponent.self) {
      var physicsBody = PhysicsBodyComponent(mode: .dynamic)
      physicsBody.material = PhysicsMaterialResource.generate(friction: 0.1, restitution: 0.95)
      physicsBody.massProperties.mass = 0.05
      physicsBody.isAffectedByGravity = false
      physicsBody.linearDamping = 0.1
      physicsBody.angularDamping = 0.5
      entity.components.set(physicsBody)

      entity.components.set(BubbleComponent())
      entity.components.set(PopComponent())

      if var col = entity.components[CollisionComponent.self] {
        col.filter = CollisionFilter(group: BubbleCollisionGroup.bubble, mask: .all)
        entity.components.set(col)
      }

      entity.position += SIMD3<Float>(
        Float.random(in: -0.5...0.5),
        Float.random(in: -0.5...0.5),
        Float.random(in: -0.5...0.5)
      )

      var motion = PhysicsMotionComponent()
      motion.linearVelocity = [
        Float.random(in: -0.2...0.2),
        Float.random(in: -0.2...0.2),
        Float.random(in: -0.2...0.2),
      ]
      entity.components.set(motion)
    }
    for child in entity.children {
      setupPhysics(for: child)
    }
  }

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

  func handleCollision(_ event: CollisionEvents.Began) {}

  func spawnNewBubble(at position: SIMD3<Float>? = nil, withVelocity velocity: SIMD3<Float>? = nil)
  {
    guard let template = bubbleTemplate else { return }

    let newBubble = template.clone(recursive: true)

    var bubbleComp = BubbleComponent()
    bubbleComp.spawnTime = Date()
    newBubble.components.set(bubbleComp)

    newBubble.position =
      position
      ?? SIMD3<Float>(
        Float.random(in: -0.5...0.5),
        Float.random(in: 0.5...1.5),
        Float.random(in: -0.8...(-0.2))
      )

    if var motion = newBubble.components[PhysicsMotionComponent.self] {
      motion.linearVelocity =
        velocity ?? [
          Float.random(in: -0.5...0.5),
          Float.random(in: -0.5...0.5),
          Float.random(in: -0.5...0.5),
        ]
      newBubble.components.set(motion)
    }

    rootEntity.addChild(newBubble)
  }

  // MARK: - Gestures

  func checkBlowingGesture(anchor: HandAnchor) {
    guard anchor.isTracked, let skeleton = anchor.handSkeleton else { return }

    let indexTip = skeleton.joint(.indexFingerTip)
    let thumbTip = skeleton.joint(.thumbTip)
    let indexKnuckle = skeleton.joint(.indexFingerIntermediateBase)

    guard indexTip.isTracked, thumbTip.isTracked, indexKnuckle.isTracked else { return }

    let originFromAnchor = anchor.originFromAnchorTransform
    let indexPos = (originFromAnchor * indexTip.anchorFromJointTransform).columns.3.xyz
    let thumbPos = (originFromAnchor * thumbTip.anchorFromJointTransform).columns.3.xyz
    let knucklePos = (originFromAnchor * indexKnuckle.anchorFromJointTransform).columns.3.xyz

    guard abs(lastBlowTime.timeIntervalSinceNow) > 0.3 else { return }

    let tipsDistance = distance(indexPos, thumbPos)
    let isPinch = tipsDistance < 0.04
    let knuckleToThumbDistance = distance(knucklePos, thumbPos)
    let isOShape = isPinch && knuckleToThumbDistance > 0.03

    guard isOShape else { return }

    guard
      let deviceAnchor = arManager.worldTracking.queryDeviceAnchor(
        atTimestamp: CACurrentMediaTime())
    else { return }
    let headPos = deviceAnchor.originFromAnchorTransform.columns.3.xyz
    let wandCenter = (indexPos + thumbPos) / 2.0
    let wandToHeadDistance = distance(wandCenter, headPos)

    guard wandToHeadDistance < 0.20 else { return }

    let blowDir = normalize(wandCenter - headPos)
    let blowVelocity = blowDir * 0.6
    let spawnPos = wandCenter + (blowDir * 0.05)

    spawnNewBubble(at: spawnPos, withVelocity: blowVelocity)
    lastBlowTime = Date()
  }
}

extension SIMD4<Float> {
  var xyz: SIMD3<Float> { SIMD3<Float>(x, y, z) }
}

#Preview(immersionStyle: .mixed) {
  ImmersiveView()
    .environment(AppModel())
}
