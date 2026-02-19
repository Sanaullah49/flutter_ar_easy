/// Types of plane detection supported by the AR session.
enum PlaneDetection { horizontal, vertical, both, none }

/// Source type for 3D models.
enum ArSourceType { asset, file, url }

/// Current state of the AR session.
enum ArSessionState {
  uninitialized,
  initializing,
  ready,
  tracking,
  trackingLost,
  error,
  disposed,
}

/// Types of AR objects that can be placed.
enum ArObjectType { cube, sphere, cylinder, model }

/// Supported model formats.
enum ModelFormat { glb, gltf, usdz, obj, unknown }

extension ModelFormatDetector on String {
  ModelFormat get detectedFormat {
    final lower = toLowerCase();
    if (lower.endsWith('.glb')) return ModelFormat.glb;
    if (lower.endsWith('.gltf')) return ModelFormat.gltf;
    if (lower.endsWith('.usdz')) return ModelFormat.usdz;
    if (lower.endsWith('.obj')) return ModelFormat.obj;
    return ModelFormat.unknown;
  }
}
