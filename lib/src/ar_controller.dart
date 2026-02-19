import 'dart:async';

import 'package:flutter/services.dart';

import 'ar_config.dart';
import 'ar_enums.dart';
import 'ar_exceptions.dart';
import 'ar_model.dart';

/// Callback types for AR events.
typedef ArPlaneDetectedCallback = void Function(ArPlane plane);
typedef ArSessionStateCallback = void Function(ArSessionState state);
typedef ArErrorCallback = void Function(ArException error);
typedef ArNodeTappedCallback = void Function(String nodeId);

/// Main controller for AR interactions.
///
/// This controller manages the AR session, handles model loading/placement,
/// and communicates with native ARCore/ARKit implementations.
class ArController {
  final int _viewId;
  late final MethodChannel _channel;
  late final EventChannel _eventChannel;

  ArSessionState _state = ArSessionState.uninitialized;
  final List<ArNode> _nodes = [];
  final List<ArPlane> _detectedPlanes = [];

  // Callbacks
  ArPlaneDetectedCallback? onPlaneDetected;
  ArSessionStateCallback? onSessionStateChanged;
  ArErrorCallback? onError;
  ArNodeTappedCallback? onNodeTapped;

  StreamSubscription? _eventSubscription;

  ArController._(this._viewId) {
    _channel = MethodChannel('flutter_ar_easy/ar_view_$_viewId');
    _eventChannel = EventChannel('flutter_ar_easy/ar_events_$_viewId');
    _setupEventListener();
  }

  /// Factory constructor - called internally when AR view is created.
  static ArController create(int viewId) {
    return ArController._(viewId);
  }

  // ─── Getters ───────────────────────────────────────────────

  ArSessionState get state => _state;
  List<ArNode> get nodes => List.unmodifiable(_nodes);
  List<ArPlane> get detectedPlanes => List.unmodifiable(_detectedPlanes);
  bool get isReady =>
      _state == ArSessionState.ready || _state == ArSessionState.tracking;
  int get nodeCount => _nodes.length;

  // ─── Session Management ────────────────────────────────────

  /// Initialize the AR session with the given configuration.
  Future<void> initialize(ArConfig config) async {
    try {
      _updateState(ArSessionState.initializing);
      await _channel.invokeMethod('initialize', config.toMap());
      _updateState(ArSessionState.ready);
    } on PlatformException catch (e) {
      _updateState(ArSessionState.error);
      final error = ArSessionException(
        e.message ?? 'Failed to initialize AR session',
      );
      onError?.call(error);
      throw error;
    }
  }

  /// Pause the AR session.
  Future<void> pause() async {
    _ensureNotDisposed();
    try {
      await _channel.invokeMethod('pause');
    } on PlatformException catch (e) {
      throw ArSessionException(e.message ?? 'Failed to pause session');
    }
  }

  /// Resume the AR session.
  Future<void> resume() async {
    _ensureNotDisposed();
    try {
      await _channel.invokeMethod('resume');
    } on PlatformException catch (e) {
      throw ArSessionException(e.message ?? 'Failed to resume session');
    }
  }

  // ─── Device Support ────────────────────────────────────────

  /// Check if the current device supports AR.
  static Future<bool> isArSupported() async {
    try {
      const channel = MethodChannel('flutter_ar_easy/support');
      final result = await channel.invokeMethod<bool>('isArSupported');
      return result ?? false;
    } on PlatformException {
      return false;
    }
  }

  // ─── Object Placement ─────────────────────────────────────

  /// Place a primitive shape (cube, sphere, cylinder) at the given position.
  Future<ArNode> placePrimitive({
    required ArObjectType type,
    ArPosition position = const ArPosition(),
    ArRotation rotation = const ArRotation(),
    ArScale scale = const ArScale.uniform(0.1),
    Map<String, dynamic> properties = const {},
  }) async {
    _ensureReady();

    final node = ArNode(
      objectType: type,
      position: position,
      rotation: rotation,
      scale: scale,
      properties: properties,
    );

    try {
      await _channel.invokeMethod('placePrimitive', node.toMap());
      _nodes.add(node);
      return node;
    } on PlatformException catch (e) {
      throw ArModelException(
        e.message ?? 'Failed to place primitive: ${type.name}',
      );
    }
  }

  /// Place a cube at the center of a detected plane (convenience method).
  Future<ArNode> placeTestCube({
    double size = 0.1,
    ArPosition? position,
  }) async {
    return placePrimitive(
      type: ArObjectType.cube,
      position: position ?? const ArPosition(x: 0, y: 0, z: -1.0),
      scale: ArScale.uniform(size),
      properties: {'color': '#FF0000'},
    );
  }

  /// Place a model from an [ArSource].
  Future<ArNode> placeModel({
    required ArSource source,
    ArPosition position = const ArPosition(),
    ArRotation rotation = const ArRotation(),
    ArScale scale = const ArScale.uniform(1.0),
  }) async {
    _ensureReady();

    final node = ArNode(
      objectType: ArObjectType.model,
      source: source,
      position: position,
      rotation: rotation,
      scale: scale,
    );

    try {
      await _channel.invokeMethod('placeModel', node.toMap());
      _nodes.add(node);
      return node;
    } on PlatformException catch (e) {
      throw ArModelException(
        e.message ?? 'Failed to place model: ${source.path}',
      );
    }
  }

  /// Place a model on a tapped position (hit test).
  Future<ArNode?> placeOnTap({
    required ArObjectType type,
    ArSource? source,
    ArScale scale = const ArScale.uniform(0.1),
  }) async {
    _ensureReady();

    try {
      final result = await _channel.invokeMethod<Map>('enableTapToPlace', {
        'objectType': type.index,
        'source': source?.toMap(),
        'scale': scale.toMap(),
      });

      if (result != null) {
        final node = ArNode.fromMap(result);
        _nodes.add(node);
        return node;
      }
      return null;
    } on PlatformException catch (e) {
      throw ArModelException(e.message ?? 'Failed to enable tap placement');
    }
  }

  // ─── Node Management ──────────────────────────────────────

  /// Remove a specific node from the scene.
  Future<void> removeNode(String nodeId) async {
    _ensureReady();

    try {
      await _channel.invokeMethod('removeNode', {'id': nodeId});
      _nodes.removeWhere((n) => n.id == nodeId);
    } on PlatformException catch (e) {
      throw ArModelException(e.message ?? 'Failed to remove node: $nodeId');
    }
  }

  /// Remove all nodes from the scene.
  Future<void> removeAllNodes() async {
    _ensureReady();

    try {
      await _channel.invokeMethod('removeAllNodes');
      _nodes.clear();
    } on PlatformException catch (e) {
      throw ArModelException(e.message ?? 'Failed to remove all nodes');
    }
  }

  /// Update a node's transform (position, rotation, scale).
  Future<void> updateNode(ArNode node) async {
    _ensureReady();

    try {
      await _channel.invokeMethod('updateNode', node.toMap());
      final index = _nodes.indexWhere((n) => n.id == node.id);
      if (index != -1) {
        _nodes[index] = node;
      }
    } on PlatformException catch (e) {
      throw ArModelException(e.message ?? 'Failed to update node');
    }
  }

  // ─── Snapshot ──────────────────────────────────────────────

  /// Take a screenshot of the current AR view.
  Future<List<int>?> takeSnapshot() async {
    _ensureReady();

    try {
      final result = await _channel.invokeMethod<List<int>>('takeSnapshot');
      return result;
    } on PlatformException catch (e) {
      throw ArSessionException(e.message ?? 'Failed to take snapshot');
    }
  }

  // ─── Event Handling ────────────────────────────────────────

  void _setupEventListener() {
    _eventSubscription = _eventChannel.receiveBroadcastStream().listen(
      _handleEvent,
      onError: _handleEventError,
    );
  }

  void _handleEvent(dynamic event) {
    if (event is! Map) return;

    final type = event['type'] as String?;

    switch (type) {
      case 'planeDetected':
        final plane = ArPlane.fromMap(event['data']);
        _detectedPlanes.add(plane);
        onPlaneDetected?.call(plane);
        break;

      case 'sessionStateChanged':
        final stateIndex = event['state'] as int;
        _updateState(ArSessionState.values[stateIndex]);
        break;

      case 'nodeTapped':
        final nodeId = event['nodeId'] as String;
        onNodeTapped?.call(nodeId);
        break;

      case 'trackingStateChanged':
        final tracking = event['isTracking'] as bool;
        _updateState(
          tracking ? ArSessionState.tracking : ArSessionState.trackingLost,
        );
        break;
    }
  }

  void _handleEventError(dynamic error) {
    final arError = ArSessionException('Event stream error: $error');
    onError?.call(arError);
  }

  void _updateState(ArSessionState newState) {
    _state = newState;
    onSessionStateChanged?.call(newState);
  }

  // ─── Validation ────────────────────────────────────────────

  void _ensureReady() {
    _ensureNotDisposed();
    if (!isReady) {
      throw const ArSessionException(
        'AR session is not ready. Call initialize() first.',
      );
    }
  }

  void _ensureNotDisposed() {
    if (_state == ArSessionState.disposed) {
      throw const ArSessionException('AR controller has been disposed.');
    }
  }

  // ─── Cleanup ───────────────────────────────────────────────

  /// Dispose of the controller and release all resources.
  Future<void> dispose() async {
    if (_state == ArSessionState.disposed) return;

    try {
      _eventSubscription?.cancel();
      await _channel.invokeMethod('dispose');
    } catch (_) {
      // Ignore errors during dispose.
    } finally {
      _nodes.clear();
      _detectedPlanes.clear();
      _updateState(ArSessionState.disposed);
    }
  }
}
