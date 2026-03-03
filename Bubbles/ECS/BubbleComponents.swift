//
//  BubbleComponents.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import Foundation
import RealityKit

/// Tag component to identify a bubble entity and track its lifecycle.
public struct BubbleComponent: Component {
  public var spawnTime: Date = Date()

  public init(spawnTime: Date = Date()) {
    self.spawnTime = spawnTime
  }
}

/// Component to manage the disintegration "pop" animation state.
public struct PopComponent: Component {
  public var progress: Float = 0
  public var isPopping: Bool = false

  public init(progress: Float = 0, isPopping: Bool = false) {
    self.progress = progress
    self.isPopping = isPopping
  }
}

/// Defines collision bitmasks for physical interactions.
public enum BubbleCollisionGroup {
  public static let bubble = CollisionGroup(rawValue: 1 << 0)
  public static let hand = CollisionGroup(rawValue: 1 << 1)
  public static let scene = CollisionGroup(rawValue: 1 << 2)
}
