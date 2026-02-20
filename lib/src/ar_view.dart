import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'ar_config.dart';
import 'ar_controller.dart';

/// Callback when the AR view is created and ready.
typedef ArViewCreatedCallback = void Function(ArController controller);

/// The main AR view widget.
///
/// This widget displays the AR camera feed and provides an [ArController]
/// for interacting with the AR scene.
///
/// ```dart
/// ArView(
///   config: ArConfig(
///     planeDetection: PlaneDetection.horizontal,
///     showDebugPlanes: true,
///   ),
///   onCreated: (controller) {
///     // Use controller to place models, etc.
///   },
/// )
/// ```
class ArView extends StatefulWidget {
  /// Configuration for the AR session.
  final ArConfig config;

  /// Called when the AR view is created and the controller is ready.
  final ArViewCreatedCallback onCreated;

  /// Called when an error occurs.
  final ArErrorCallback? onError;

  /// Widget to show while AR is loading.
  final Widget? loadingWidget;

  /// Widget to show when AR is not supported.
  final Widget? unsupportedWidget;

  /// Whether to show a default loading indicator.
  final bool showDefaultLoading;

  const ArView({
    super.key,
    required this.onCreated,
    this.config = const ArConfig(),
    this.onError,
    this.loadingWidget,
    this.unsupportedWidget,
    this.showDefaultLoading = true,
  });

  @override
  State<ArView> createState() => _ArViewState();
}

class _ArViewState extends State<ArView> with WidgetsBindingObserver {
  ArController? _controller;
  bool _isLoading = true;
  bool _isSupported = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkSupport();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (_controller == null) return;

    switch (state) {
      case AppLifecycleState.paused:
        _controller!.pause();
        break;
      case AppLifecycleState.resumed:
        _controller!.resume();
        break;
      default:
        break;
    }
  }

  Future<void> _checkSupport() async {
    final supported = await ArController.isArSupported();
    if (mounted) {
      setState(() {
        _isSupported = supported;
        if (!supported) _isLoading = false;
      });
    }
  }

  Widget _buildPermissionDeniedWidget() {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.camera_alt_outlined,
                color: Colors.orangeAccent,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'Camera Permission Required',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'AR features need camera access to work.\n'
                'Please grant permission in Settings.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () async {
                  final controller = ArController.create(0); // Temp controller
                  try {
                    await controller.openAppSettings();
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text('Error: $e')));
                    }
                  }
                },
                icon: const Icon(Icons.settings),
                label: const Text('Open Settings'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orangeAccent,
                  foregroundColor: Colors.black,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _onPlatformViewCreated(int viewId) async {
    final controller = ArController.create(viewId);

    controller.onError = (error) {
      widget.onError?.call(error);
      if (mounted) {
        setState(() {
          _errorMessage = error.message;
        });
      }
    };

    try {
      await controller.initialize(widget.config);
      _controller = controller;

      if (mounted) {
        setState(() => _isLoading = false);
      }

      widget.onCreated(controller);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) {
      return widget.unsupportedWidget ?? _buildUnsupportedWidget();
    }

    if (_errorMessage?.contains('PERMISSION') == true) {
      return _buildPermissionDeniedWidget();
    }

    if (_errorMessage != null) {
      return _buildErrorWidget(_errorMessage!);
    }

    return Stack(
      children: [
        _buildPlatformView(),
        if (_isLoading)
          widget.loadingWidget ??
              (widget.showDefaultLoading
                  ? _buildDefaultLoading()
                  : const SizedBox.shrink()),
      ],
    );
  }

  Widget _buildPlatformView() {
    const viewType = 'flutter_ar_easy/ar_view';
    final creationParams = widget.config.toMap();

    if (defaultTargetPlatform == TargetPlatform.android) {
      return AndroidView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      );
    }

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return UiKitView(
        viewType: viewType,
        creationParams: creationParams,
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: _onPlatformViewCreated,
        gestureRecognizers: <Factory<OneSequenceGestureRecognizer>>{
          Factory<OneSequenceGestureRecognizer>(() => EagerGestureRecognizer()),
        },
      );
    }

    return _buildUnsupportedWidget();
  }

  Widget _buildDefaultLoading() {
    return Container(
      color: Colors.black,
      child: const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: Colors.white),
            SizedBox(height: 16),
            Text(
              'Initializing AR...',
              style: TextStyle(color: Colors.white, fontSize: 16),
            ),
            SizedBox(height: 8),
            Text(
              'Point your camera at a flat surface',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupportedWidget() {
    return Container(
      color: Colors.grey[900],
      child: const Center(
        child: Padding(
          padding: EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.view_in_ar, color: Colors.white54, size: 64),
              SizedBox(height: 16),
              Text(
                'AR Not Supported',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              SizedBox(height: 8),
              Text(
                'This device does not support augmented reality.\n'
                'Please try on a compatible device.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildErrorWidget(String error) {
    return Container(
      color: Colors.grey[900],
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                color: Colors.redAccent,
                size: 64,
              ),
              const SizedBox(height: 16),
              const Text(
                'AR Error',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                error,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white60, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
