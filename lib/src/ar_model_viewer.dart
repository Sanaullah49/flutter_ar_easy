import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'ar_config.dart';
import 'ar_controller.dart';
import 'ar_enums.dart';
import 'ar_model.dart';
import 'ar_view.dart';

/// A prebuilt, ready-to-use AR model viewer widget.
///
/// This is the "killer feature" — usable in 5 lines of code:
///
/// ```dart
/// ArModelViewer(
///   modelUrl: 'https://example.com/chair.glb',
///   enableTapToPlace: true,
/// )
/// ```
class ArModelViewer extends StatefulWidget {
  /// URL or asset path for the 3D model.
  final String modelPath;

  /// Source type (asset, url, file).
  final ArSourceType sourceType;

  /// Enable tap-to-place functionality.
  final bool enableTapToPlace;

  /// Enable rotation gestures.
  final bool enableRotation;

  /// Enable scale gestures.
  final bool enableScaling;

  /// Initial scale of the model.
  final double initialScale;

  /// Show plane detection debug overlay.
  final bool showDebugPlanes;

  /// Plane detection mode.
  final PlaneDetection planeDetection;

  /// Custom loading widget.
  final Widget? loadingWidget;

  /// Custom AR not supported widget.
  final Widget? unsupportedWidget;

  /// Called when a model is placed.
  final void Function(ArNode node)? onModelPlaced;

  /// Called when an error occurs.
  final void Function(String error)? onError;

  const ArModelViewer({
    super.key,
    required this.modelPath,
    this.sourceType = ArSourceType.url,
    this.enableTapToPlace = true,
    this.enableRotation = true,
    this.enableScaling = true,
    this.initialScale = 1.0,
    this.showDebugPlanes = false,
    this.planeDetection = PlaneDetection.horizontal,
    this.loadingWidget,
    this.unsupportedWidget,
    this.onModelPlaced,
    this.onError,
  });

  @override
  State<ArModelViewer> createState() => _ArModelViewerState();
}

class _ArModelViewerState extends State<ArModelViewer> {
  ArController? _controller;
  ArNode? _activeModelNode;
  bool _modelPlaced = false;
  bool _isModelLoaded = false;
  bool _isPreparingModel = false;
  bool _isTransformSyncInFlight = false;
  bool _hasPendingTransformSync = false;
  double? _baseGestureScale;
  double? _baseGestureYaw;
  String? _statusMessage;

  ArSource get _source {
    switch (widget.sourceType) {
      case ArSourceType.asset:
        return ArSource.asset(widget.modelPath);
      case ArSourceType.file:
        return ArSource.file(widget.modelPath);
      case ArSourceType.url:
        return ArSource.url(widget.modelPath);
    }
  }

  void _onArCreated(ArController controller) {
    _controller = controller;

    controller.onPlaneDetected = (_) {
      if (!mounted) return;
      if (_modelPlaced || !_isModelLoaded) return;
      setState(() {
        _statusMessage = widget.enableTapToPlace
            ? 'Plane detected! Tap to place model.'
            : 'Plane detected. Placing model...';
      });
    };

    _prepareModel();
  }

  Future<void> _prepareModel() async {
    final controller = _controller;
    if (controller == null || _isPreparingModel || _isModelLoaded) return;

    if (!mounted) return;
    setState(() {
      _isPreparingModel = true;
      _statusMessage = 'Loading model...';
    });

    try {
      await controller.loadModel(source: _source, scale: widget.initialScale);
      if (!mounted) return;
      setState(() {
        _isModelLoaded = true;
        _statusMessage = widget.enableTapToPlace
            ? 'Move your device to detect a surface...'
            : 'Model loaded. Placing model...';
      });

      if (!widget.enableTapToPlace) {
        await _autoPlaceModel();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _statusMessage = null);
      widget.onError?.call(e.toString());
    } finally {
      if (mounted) {
        setState(() => _isPreparingModel = false);
      }
    }
  }

  Future<void> _autoPlaceModel() async {
    if (_controller == null || _modelPlaced || !_isModelLoaded) return;

    try {
      final node = await _controller!.placeModel(
        position: const ArPosition(x: 0, y: 0, z: -1.5),
      );

      if (!mounted) return;
      setState(() {
        _activeModelNode = node;
        _modelPlaced = true;
        _statusMessage = _gestureHint;
      });

      widget.onModelPlaced?.call(node);
    } catch (e) {
      widget.onError?.call(e.toString());
    }
  }

  Future<void> _handleTapToPlace(TapUpDetails details) async {
    final controller = _controller;
    if (controller == null || _modelPlaced || !_isModelLoaded) return;

    try {
      final node = await controller.placeModelAtScreenPosition(
        screenX: details.localPosition.dx,
        screenY: details.localPosition.dy,
      );

      if (!mounted) return;
      setState(() {
        _activeModelNode = node;
        _modelPlaced = true;
        _statusMessage = _gestureHint;
      });

      widget.onModelPlaced?.call(node);
    } catch (e) {
      widget.onError?.call(e.toString());
    }
  }

  String? get _gestureHint {
    final actions = <String>[];
    if (widget.enableRotation) actions.add('rotate');
    if (widget.enableScaling) actions.add('scale');
    if (actions.isEmpty || !_modelPlaced) return null;
    if (actions.length == 1) return 'Use two fingers to ${actions.first}.';
    return 'Use two fingers to rotate and scale.';
  }

  bool get _shouldShowGestureOverlay =>
      _modelPlaced && (widget.enableRotation || widget.enableScaling);

  void _onTransformStart(ScaleStartDetails details) {
    final node = _activeModelNode;
    if (node == null || !_shouldShowGestureOverlay) return;

    _baseGestureScale = node.scale.x;
    _baseGestureYaw = node.rotation.yaw;
  }

  void _onTransformUpdate(ScaleUpdateDetails details) {
    final node = _activeModelNode;
    if (node == null || !_shouldShowGestureOverlay) return;

    var nextScale = node.scale.x;
    var nextYaw = node.rotation.yaw;
    var changed = false;

    if (widget.enableScaling && _baseGestureScale != null) {
      nextScale = (_baseGestureScale! * details.scale).clamp(0.05, 5.0);
      changed = true;
    }

    if (widget.enableRotation &&
        _baseGestureYaw != null &&
        details.pointerCount > 1) {
      nextYaw = _baseGestureYaw! + (details.rotation * 180 / math.pi);
      changed = true;
    }

    if (!changed) return;

    node.scale = ArScale.uniform(nextScale);
    node.rotation = ArRotation(
      pitch: node.rotation.pitch,
      yaw: nextYaw,
      roll: node.rotation.roll,
    );

    _syncNodeTransform();
  }

  void _onTransformEnd(ScaleEndDetails details) {
    _baseGestureScale = null;
    _baseGestureYaw = null;
  }

  void _syncNodeTransform() {
    if (_isTransformSyncInFlight) {
      _hasPendingTransformSync = true;
      return;
    }

    final controller = _controller;
    final node = _activeModelNode;
    if (controller == null || node == null) return;

    _isTransformSyncInFlight = true;
    controller
        .updateNode(node)
        .catchError((error) {
          // Fix: Reset flag on error to prevent permanent blocking
          _isTransformSyncInFlight = false;
          _hasPendingTransformSync = false;
          widget.onError?.call(error.toString());
        })
        .whenComplete(() {
          _isTransformSyncInFlight = false;
          if (_hasPendingTransformSync) {
            _hasPendingTransformSync = false;
            _syncNodeTransform();
          }
        });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ArView(
          config: ArConfig(
            planeDetection: widget.planeDetection,
            showDebugPlanes: widget.showDebugPlanes,
            lightEstimation: true,
          ),
          onCreated: _onArCreated,
          loadingWidget: widget.loadingWidget,
          unsupportedWidget: widget.unsupportedWidget,
          onError: (error) => widget.onError?.call(error.message),
        ),

        if ((widget.enableTapToPlace && !_modelPlaced) ||
            _shouldShowGestureOverlay)
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTapUp: widget.enableTapToPlace && !_modelPlaced
                  ? _handleTapToPlace
                  : null,
              onScaleStart: _shouldShowGestureOverlay
                  ? _onTransformStart
                  : null,
              onScaleUpdate: _shouldShowGestureOverlay
                  ? _onTransformUpdate
                  : null,
              onScaleEnd: _shouldShowGestureOverlay ? _onTransformEnd : null,
            ),
          ),

        // Status overlay
        if (_statusMessage != null)
          Positioned(
            bottom: 100,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Text(
                  _statusMessage!,
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
              ),
            ),
          ),

        // Controls overlay
        if (_modelPlaced)
          Positioned(
            bottom: 40,
            right: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildControlButton(
                  icon: Icons.delete_outline,
                  label: 'Clear',
                  onTap: () async {
                    await _controller?.removeAllNodes();
                    if (!mounted) return;
                    setState(() {
                      _activeModelNode = null;
                      _modelPlaced = false;
                      _statusMessage = widget.enableTapToPlace
                          ? 'Tap to place model.'
                          : null;
                    });
                  },
                ),
                const SizedBox(height: 12),
                _buildControlButton(
                  icon: Icons.refresh,
                  label: 'Replace',
                  onTap: () async {
                    await _controller?.removeAllNodes();
                    if (!mounted) return;
                    setState(() {
                      _activeModelNode = null;
                      _modelPlaced = false;
                      _statusMessage = widget.enableTapToPlace
                          ? 'Tap to place model.'
                          : null;
                    });
                    if (!widget.enableTapToPlace) {
                      _autoPlaceModel();
                    }
                  },
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ],
        ),
      ),
    );
  }
}
