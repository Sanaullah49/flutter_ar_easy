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
  bool _modelPlaced = false;
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

    controller.onPlaneDetected = (plane) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Plane detected! Tap to place model.';
      });
    };

    if (widget.enableTapToPlace) {
      _enableTapPlacement();
    } else {
      _autoPlaceModel();
    }
  }

  void _enableTapPlacement() {
    if (!mounted) return;
    setState(() {
      _statusMessage = 'Move your device to detect a surface...';
    });

    _controller?.onNodeTapped = (nodeId) {
      // Handle node tap for rotation/scaling in future phases
    };
  }

  Future<void> _autoPlaceModel() async {
    if (_controller == null || _modelPlaced) return;

    try {
      final node = await _controller!.placeModel(
        source: _source,
        scale: ArScale.uniform(widget.initialScale),
        position: const ArPosition(x: 0, y: 0, z: -1.5),
      );

      if (!mounted) return;
      setState(() {
        _modelPlaced = true;
        _statusMessage = null;
      });

      widget.onModelPlaced?.call(node);
    } catch (e) {
      widget.onError?.call(e.toString());
    }
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
                    setState(() => _modelPlaced = false);
                  },
                ),
                const SizedBox(height: 12),
                _buildControlButton(
                  icon: Icons.refresh,
                  label: 'Replace',
                  onTap: () async {
                    await _controller?.removeAllNodes();
                    if (!mounted) return;
                    setState(() => _modelPlaced = false);
                    _autoPlaceModel();
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
