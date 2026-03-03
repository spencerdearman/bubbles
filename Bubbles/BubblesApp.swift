//
//  BubblesApp.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import RealityKit
import SwiftUI

@main
struct BubblesApp: App {
  @State private var appModel = AppModel()

  init() {
    BubbleComponent.registerComponent()
    PopComponent.registerComponent()
    BubblePhysicsSystem.registerSystem()
  }

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
    .immersionStyle(
      selection: Binding(
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
