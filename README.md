# Bubbles - visionOS 

An immersive, physics-driven bubble simulation designed for Apple Vision Pro. Interact with bubbles that respond to your hands and your physical environment.

## Features

- **Organic Physics Engine**: Custom buoyancy and turbulence systems create light, fluttering movement that feels like real soap bubbles.
- **Environment Interaction**: Bubbles use **Scene Reconstruction** to realistically bounce off your walls, furniture, and floors.
- **Hand Interaction**: 
  - **Batting**: Swat at bubbles with your hands.
  - **Direct Gestures**: Tap to push, long-press to pop.
- **Blowing Gesture**: Form an "O" shape with your hand near your mouth to "blow" new bubbles into your space.
- **Visual Sophistication**: High-quality shader-based popping effects and physics-driven oscillations.

<video src="Bubble-Demo.mp4" width="100%" controls autoplay loop muted></video>

## Frameworks

- **RealityKit**: Core rendering and Entity-Component-System (ECS) architecture.
- **ARKit**: Hand tracking, World tracking, and Scene Reconstruction.
- **SwiftUI**: Main application structure and immersive space management.
- **Custom ECS**: 
  - `BubblePhysicsSystem`: Handles frame-by-frame buoyancy and drag calculations.
  - `PopComponent`: Manages state-based disintegration animations.

## Setup

1. **Hardware**: Requires Apple Vision Pro or the visionOS Simulator.
2. **Setup**: Open `Bubbles.xcodeproj` in Xcode 15.2 or later.
3. **Run**: Target your device or simulator and hit **Run**.
4. **Interaction**:
   - Look at a bubble and **Tap** to apply an impulse.
   - **Long Press** a bubble to watch it pop.
   - Hold your hand near your mouth in an **"O" shape** to blow new ones.
   - Use your hands to bat them around the room!

## Additional Notes

- **Performance**: Bubbles have a 30-second lifespan to ensure the scene remains performant.
- **Collision Filtering**: Tuned collision masks ensure bubbles interact with hands and the room without getting "stuck" in complex geometry.
- **Kinematic Hands**: Specifically selected joints (fingertips, wrist) are used for interaction to provide a clean, predictable physical response.
