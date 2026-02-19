import 'ar_enums.dart';

/// Configuration for the AR session.
class ArConfig {
  /// Type of plane detection.
  final PlaneDetection planeDetection;

  /// Whether to show debug visualization of detected planes.
  final bool showDebugPlanes;

  /// Whether to show feature points.
  final bool showFeaturePoints;

  /// Whether to auto-focus the camera.
  final bool autoFocus;

  /// Whether to enable light estimation.
  final bool lightEstimation;

  /// Maximum number of models allowed in scene.
  final int maxModels;

  /// Background color when AR is loading (hex string).
  final String? loadingBackgroundColor;

  const ArConfig({
    this.planeDetection = PlaneDetection.horizontal,
    this.showDebugPlanes = false,
    this.showFeaturePoints = false,
    this.autoFocus = true,
    this.lightEstimation = true,
    this.maxModels = 10,
    this.loadingBackgroundColor,
  });

  Map<String, dynamic> toMap() {
    return {
      'planeDetection': planeDetection.index,
      'showDebugPlanes': showDebugPlanes,
      'showFeaturePoints': showFeaturePoints,
      'autoFocus': autoFocus,
      'lightEstimation': lightEstimation,
      'maxModels': maxModels,
      'loadingBackgroundColor': loadingBackgroundColor,
    };
  }

  ArConfig copyWith({
    PlaneDetection? planeDetection,
    bool? showDebugPlanes,
    bool? showFeaturePoints,
    bool? autoFocus,
    bool? lightEstimation,
    int? maxModels,
    String? loadingBackgroundColor,
  }) {
    return ArConfig(
      planeDetection: planeDetection ?? this.planeDetection,
      showDebugPlanes: showDebugPlanes ?? this.showDebugPlanes,
      showFeaturePoints: showFeaturePoints ?? this.showFeaturePoints,
      autoFocus: autoFocus ?? this.autoFocus,
      lightEstimation: lightEstimation ?? this.lightEstimation,
      maxModels: maxModels ?? this.maxModels,
      loadingBackgroundColor:
          loadingBackgroundColor ?? this.loadingBackgroundColor,
    );
  }
}
