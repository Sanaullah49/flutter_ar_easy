# flutter_ar_easy

**A simplified AR integration wrapper for Flutter that makes AR usable in 5-10 lines of code.**

Wraps ARCore (Android) and ARKit (iOS) with a unified Dart API, making it simple to place 3D models in augmented reality.

---

## ✨ Features

- ✅ **Simple API** - Place AR objects in 5 lines of code
- ✅ **Cross-platform** - Works on Android (ARCore) and iOS (ARKit)
- ✅ **Plane Detection** - Automatic horizontal/vertical plane detection
- ✅ **Primitive Shapes** - Built-in cubes, spheres, cylinders
- ✅ **3D Model Support** - Load GLB, GLTF, USDZ models
- ✅ **Prebuilt Widgets** - Ready-to-use AR viewer components
- ✅ **Debug Mode** - Visualize detected planes and feature points
- ✅ **Lifecycle Management** - Handles pause/resume automatically

---

## 🚀 Quick Start

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_ar_easy: ^0.1.0
Android Setup
Minimum SDK: Set minSdkVersion to 24 in android/app/build.gradle:
gradle

android {
    defaultConfig {
        minSdkVersion 24
    }
}
Permissions: Add to android/app/src/main/AndroidManifest.xml:
XML

<uses-permission android:name="android.permission.CAMERA" />
<uses-feature android:name="android.hardware.camera.ar" android:required="true" />

<application>
    <meta-data
        android:name="com.google.ar.core"
        android:value="required" />
</application>
iOS Setup
Minimum iOS: Set to 12.0 in ios/Podfile:
Ruby

platform :ios, '12.0'
Permissions: Add to ios/Runner/Info.plist:
XML

<key>NSCameraUsageDescription</key>
<string>We need camera access for AR features</string>
📱 Usage
Basic AR View
dart

import 'package:flutter_ar_easy/flutter_ar_easy.dart';

class MyArScreen extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArView(
        config: ArConfig(
          planeDetection: PlaneDetection.horizontal,
          showDebugPlanes: true,
        ),
        onCreated: (controller) {
          // AR is ready! Place objects here
        },
      ),
    );
  }
}
Place a Test Cube
dart

ArView(
  onCreated: (controller) async {
    // Wait for plane detection
    await Future.delayed(Duration(seconds: 2));
    
    // Place a red cube
    await controller.placeTestCube(size: 0.1);
  },
)
Place Custom Shapes
dart

// Place a blue sphere
await controller.placePrimitive(
  type: ArObjectType.sphere,
  scale: ArScale.uniform(0.15),
  properties: {'color': '#0000FF'},
);

// Place a green cylinder
await controller.placePrimitive(
  type: ArObjectType.cylinder,
  scale: ArScale.uniform(0.2),
  properties: {'color': '#00FF00'},
);
Prebuilt Model Viewer (Easiest!)
dart

ArModelViewer(
  modelPath: 'assets/models/chair.glb',
  sourceType: ArSourceType.asset,
  enableTapToPlace: true,
  enableRotation: true,
  initialScale: 1.0,
  onModelPlaced: (node) {
    print('Model placed at: ${node.position}');
  },
)
🎮 API Reference
ArController
Main controller for AR interactions:

dart

// Check device support
bool supported = await ArController.isArSupported();

// Place objects
ArNode node = await controller.placePrimitive(
  type: ArObjectType.cube,
  position: ArPosition(x: 0, y: 0, z: -1),
  scale: ArScale.uniform(0.1),
);

// Manage nodes
await controller.removeNode(node.id);
await controller.removeAllNodes();
await controller.updateNode(node);

// Session control
await controller.pause();
await controller.resume();
await controller.dispose();
Callbacks
dart

controller.onPlaneDetected = (plane) {
  print('Plane detected: ${plane.width}x${plane.height}');
};

controller.onSessionStateChanged = (state) {
  print('AR state: $state');
};

controller.onNodeTapped = (nodeId) {
  print('Node tapped: $nodeId');
};

controller.onError = (error) {
  print('AR error: ${error.message}');
};
🔧 Configuration
dart

ArConfig(
  planeDetection: PlaneDetection.horizontal,  // horizontal | vertical | both
  showDebugPlanes: true,                       // Show plane overlays
  showFeaturePoints: false,                    // Show tracking points
  lightEstimation: true,                       // Enable realistic lighting
  maxModels: 10,                               // Max models in scene
)
📋 Roadmap
Phase 1 (Current) ✅
 ARCore Android integration
 Plane detection
 Primitive shapes (cube, sphere, cylinder)
 Debug visualization
 Lifecycle management
Phase 2 (Current) ✅
 Load 3D models (GLB/GLTF/asset/file/url)
 Remote model loading with disk caching
 Tap-to-place model placement support
 `loadModel()` + `placeModel()` preload/placement workflow
Phase 3
 iOS ARKit integration
 Cross-platform API unification
Phase 4
 Gestures (rotate, scale, move)
 Snapshot/screenshot
 Occlusion
Phase 5
 Face tracking
 Image tracking
 Persistent anchors
🐛 Known Issues
Android Only: iOS support coming in Phase 3
Model Loading: Best support is currently GLB/GLTF; large models can still impact frame rate.
ARCore Devices: Requires ARCore supported device
🤝 Contributing
Contributions welcome! Please read CONTRIBUTING.md.

📄 License
MIT License - see LICENSE file.

🙏 Credits
Built with:

ARCore by Google
Sceneform (community fork)
ARKit by Apple
📞 Support
🐛 Issues
💬 Discussions
📧 Email: your@email.com
Made with ❤️ for the Flutter community
