//
//  AppModel.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import SwiftUI

/// Maintains app-wide state
@MainActor
@Observable
class AppModel {
    let immersiveSpaceID = "ImmersiveSpace"
    enum ImmersiveSpaceState {
        case closed
        case inTransition
        case open
    }
    var immersiveSpaceState = ImmersiveSpaceState.closed
    
    // Immersion options
    // 0: mixed, 1: progressive, 2: full
    var currentImmersionStyleInt: Int = 0
    
    // Event trigger for spawning bubbles
    let spawnBubbleEvent = NotificationCenter.default.publisher(for: Notification.Name("SpawnBubble"))
    
    func spawnBubble() {
        NotificationCenter.default.post(name: Notification.Name("SpawnBubble"), object: nil)
    }
}
