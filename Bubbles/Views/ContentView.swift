//
//  ContentView.swift
//  Bubbles
//
//  Created by Spencer Dearman on 2/16/26.
//

import RealityKit
import RealityKitContent
import SwiftUI

struct ContentView: View {
  @Environment(AppModel.self) private var appModel

  var body: some View {
    VStack(spacing: 20) {
      Text("Bubbles")
        .font(.extraLargeTitle)

      ToggleImmersiveSpaceButton()

      if appModel.immersiveSpaceState == .open {
        @Bindable var bindableAppModel = appModel
        Picker("Immersion Style", selection: $bindableAppModel.currentImmersionStyleInt) {
          Text("Mixed").tag(0)
          Text("Progressive").tag(1)
          Text("Full").tag(2)
        }
        .pickerStyle(.segmented)
        .padding(.horizontal, 40)
      }
    }
    .frame(width: 500, height: 350)
    .padding()
  }
}

#Preview(windowStyle: .automatic) {
  ContentView()
    .environment(AppModel())
}
