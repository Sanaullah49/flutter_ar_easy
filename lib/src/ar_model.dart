import 'dart:math';

import 'ar_enums.dart';

/// Represents a 3D position in AR space.
class ArPosition {
  final double x;
  final double y;
  final double z;

  const ArPosition({this.x = 0.0, this.y = 0.0, this.z = 0.0});

  Map<String, double> toMap() => {'x': x, 'y': y, 'z': z};

  factory ArPosition.fromMap(Map<dynamic, dynamic> map) {
    return ArPosition(
      x: (map['x'] as num?)?.toDouble() ?? 0.0,
      y: (map['y'] as num?)?.toDouble() ?? 0.0,
      z: (map['z'] as num?)?.toDouble() ?? 0.0,
    );
  }

  ArPosition operator +(ArPosition other) {
    return ArPosition(x: x + other.x, y: y + other.y, z: z + other.z);
  }

  double distanceTo(ArPosition other) {
    return sqrt(
      pow(x - other.x, 2) + pow(y - other.y, 2) + pow(z - other.z, 2),
    );
  }

  @override
  String toString() => 'ArPosition($x, $y, $z)';
}

/// Represents a 3D rotation in AR space (Euler angles in degrees).
class ArRotation {
  final double pitch; // X-axis
  final double yaw; // Y-axis
  final double roll; // Z-axis

  const ArRotation({this.pitch = 0.0, this.yaw = 0.0, this.roll = 0.0});

  Map<String, double> toMap() => {'pitch': pitch, 'yaw': yaw, 'roll': roll};

  factory ArRotation.fromMap(Map<dynamic, dynamic> map) {
    return ArRotation(
      pitch: (map['pitch'] as num?)?.toDouble() ?? 0.0,
      yaw: (map['yaw'] as num?)?.toDouble() ?? 0.0,
      roll: (map['roll'] as num?)?.toDouble() ?? 0.0,
    );
  }
}

/// Represents a 3D scale.
class ArScale {
  final double x;
  final double y;
  final double z;

  const ArScale({this.x = 1.0, this.y = 1.0, this.z = 1.0});

  /// Uniform scale.
  const ArScale.uniform(double scale) : x = scale, y = scale, z = scale;

  Map<String, double> toMap() => {'x': x, 'y': y, 'z': z};

  factory ArScale.fromMap(Map<dynamic, dynamic> map) {
    return ArScale(
      x: (map['x'] as num?)?.toDouble() ?? 1.0,
      y: (map['y'] as num?)?.toDouble() ?? 1.0,
      z: (map['z'] as num?)?.toDouble() ?? 1.0,
    );
  }
}

/// Source reference for a 3D model.
class ArSource {
  final ArSourceType type;
  final String path;

  const ArSource.asset(this.path) : type = ArSourceType.asset;
  const ArSource.file(this.path) : type = ArSourceType.file;
  const ArSource.url(this.path) : type = ArSourceType.url;

  ModelFormat get format => path.detectedFormat;

  Map<String, dynamic> toMap() => {'type': type.index, 'path': path};
}

/// Represents a node (object) in the AR scene.
class ArNode {
  final String id;
  final ArObjectType objectType;
  final ArSource? source;
  ArPosition position;
  ArRotation rotation;
  ArScale scale;
  final Map<String, dynamic> properties;

  ArNode({
    String? id,
    this.objectType = ArObjectType.cube,
    this.source,
    this.position = const ArPosition(),
    this.rotation = const ArRotation(),
    this.scale = const ArScale.uniform(1.0),
    this.properties = const {},
  }) : id = id ?? _generateId();

  static String _generateId() {
    final now = DateTime.now().microsecondsSinceEpoch;
    final random = Random().nextInt(99999);
    return 'ar_node_${now}_$random';
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'objectType': objectType.index,
    'source': source?.toMap(),
    'position': position.toMap(),
    'rotation': rotation.toMap(),
    'scale': scale.toMap(),
    'properties': properties,
  };

  factory ArNode.fromMap(Map<dynamic, dynamic> map) {
    return ArNode(
      id: map['id'] as String?,
      objectType: ArObjectType.values[map['objectType'] as int? ?? 0],
      position: map['position'] != null
          ? ArPosition.fromMap(map['position'])
          : const ArPosition(),
      rotation: map['rotation'] != null
          ? ArRotation.fromMap(map['rotation'])
          : const ArRotation(),
      scale: map['scale'] != null
          ? ArScale.fromMap(map['scale'])
          : const ArScale.uniform(1.0),
    );
  }
}

/// Information about a detected AR plane.
class ArPlane {
  final String id;
  final ArPosition center;
  final double width;
  final double height;
  final PlaneDetection type;

  const ArPlane({
    required this.id,
    required this.center,
    required this.width,
    required this.height,
    required this.type,
  });

  factory ArPlane.fromMap(Map<dynamic, dynamic> map) {
    return ArPlane(
      id: map['id'] as String,
      center: ArPosition.fromMap(map['center']),
      width: (map['width'] as num).toDouble(),
      height: (map['height'] as num).toDouble(),
      type: PlaneDetection.values[map['type'] as int? ?? 0],
    );
  }
}
