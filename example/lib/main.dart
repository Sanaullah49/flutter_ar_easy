import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_ar_easy/flutter_ar_easy.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter AR Easy Demo',
      theme: ThemeData.dark().copyWith(
        colorScheme: const ColorScheme.dark(
          primary: Colors.blueAccent,
          secondary: Colors.cyanAccent,
        ),
      ),
      home: const HomeScreen(),
    );
  }
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool? _arSupported;

  @override
  void initState() {
    super.initState();
    _checkSupport();
  }

  Future<void> _checkSupport() async {
    final supported = await ArController.isArSupported();
    if (!mounted) return;
    setState(() => _arSupported = supported);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Flutter AR Easy'), centerTitle: true),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Support status
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Icon(
                      _arSupported == true
                          ? Icons.check_circle
                          : _arSupported == false
                          ? Icons.cancel
                          : Icons.hourglass_empty,
                      color: _arSupported == true
                          ? Colors.green
                          : _arSupported == false
                          ? Colors.red
                          : Colors.orange,
                      size: 32,
                    ),
                    const SizedBox(width: 16),
                    Text(
                      _arSupported == null
                          ? 'Checking AR support...'
                          : _arSupported!
                          ? 'AR is supported ✓'
                          : 'AR not supported ✗',
                      style: const TextStyle(fontSize: 18),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 32),

            // Demo buttons
            _buildDemoButton(
              icon: Icons.view_in_ar,
              title: 'Basic AR View',
              subtitle: 'Plane detection + test cube',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const BasicArDemo()),
              ),
            ),

            const SizedBox(height: 16),

            _buildDemoButton(
              icon: Icons.category,
              title: 'Place Primitives',
              subtitle: 'Cubes, spheres, cylinders',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrimitivesDemo()),
              ),
            ),

            const SizedBox(height: 16),

            _buildDemoButton(
              icon: Icons.chair_alt,
              title: 'Model Viewer',
              subtitle: 'GLB from URL + tap-to-place',
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ModelViewerDemo()),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDemoButton({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return Card(
      child: ListTile(
        leading: Icon(icon, size: 40, color: Colors.cyanAccent),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: _arSupported == true ? onTap : null,
        enabled: _arSupported == true,
      ),
    );
  }
}

// ─── Basic AR Demo ─────────────────────────────────────────

class BasicArDemo extends StatefulWidget {
  const BasicArDemo({super.key});

  @override
  State<BasicArDemo> createState() => _BasicArDemoState();
}

class _BasicArDemoState extends State<BasicArDemo> {
  ArController? _controller;
  String _status = 'Initializing...';
  int _planeCount = 0;
  int _nodeCount = 0;

  void _onArCreated(ArController controller) {
    _controller = controller;

    controller.onPlaneDetected = (plane) {
      if (!mounted) return;
      setState(() {
        _planeCount++;
        _status = 'Plane detected! Tap + to place cube.';
      });
    };

    controller.onSessionStateChanged = (state) {
      if (!mounted) return;
      setState(() {
        _status = switch (state) {
          ArSessionState.ready => 'Ready - scan a surface',
          ArSessionState.tracking => 'Tracking',
          ArSessionState.trackingLost => 'Tracking lost - move slowly',
          ArSessionState.error => 'Error occurred',
          _ => _status,
        };
      });
    };

    if (!mounted) return;
    setState(() => _status = 'Scan a flat surface...');
  }

  Future<void> _placeCube() async {
    if (_controller == null) return;

    try {
      await _controller!.placeTestCube(size: 0.1);
      if (!mounted) return;
      setState(() => _nodeCount = _controller!.nodeCount);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  Future<void> _clearAll() async {
    await _controller?.removeAllNodes();
    if (!mounted) return;
    setState(() => _nodeCount = 0);
  }

  Future<void> _takeSnapshot() async {
    if (_controller == null) return;

    try {
      final bytes = await _controller!.takeSnapshot();
      if (!mounted || bytes == null || bytes.isEmpty) return;

      final imageBytes = Uint8List.fromList(bytes);
      await showDialog<void>(
        context: context,
        builder: (context) {
          return Dialog(
            backgroundColor: Colors.black87,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'AR Snapshot',
                    style: TextStyle(color: Colors.white, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(imageBytes),
                  ),
                ],
              ),
            ),
          );
        },
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Snapshot error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Basic AR View')),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.58,
            child: ClipRect(
              child: ArView(
                config: const ArConfig(
                  planeDetection: PlaneDetection.horizontal,
                  showDebugPlanes: true,
                  lightEstimation: true,
                ),
                onCreated: _onArCreated,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.85),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_status, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'Planes: $_planeCount | Nodes: $_nodeCount',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Use buttons below to test placement and snapshot.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clearAll,
                        icon: const Icon(Icons.delete),
                        label: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _takeSnapshot,
                        icon: const Icon(Icons.camera_alt),
                        label: const Text('Snapshot'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _placeCube,
                        icon: const Icon(Icons.add),
                        label: const Text('Place Cube'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Primitives Demo ───────────────────────────────────────

class PrimitivesDemo extends StatefulWidget {
  const PrimitivesDemo({super.key});

  @override
  State<PrimitivesDemo> createState() => _PrimitivesDemoState();
}

class _PrimitivesDemoState extends State<PrimitivesDemo> {
  ArController? _controller;
  ArObjectType _selectedType = ArObjectType.cube;
  double _scale = 0.1;
  String _selectedColor = '#FF0000';

  final _colors = {
    'Red': '#FF0000',
    'Blue': '#0000FF',
    'Green': '#00FF00',
    'Yellow': '#FFFF00',
    'Purple': '#800080',
    'Cyan': '#00FFFF',
  };

  void _onArCreated(ArController controller) {
    _controller = controller;
  }

  Future<void> _placeShape() async {
    if (_controller == null) return;

    try {
      await _controller!.placePrimitive(
        type: _selectedType,
        scale: ArScale.uniform(_scale),
        properties: {'color': _selectedColor},
      );
      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Error: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Place Primitives')),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.58,
            child: ClipRect(
              child: ArView(
                config: const ArConfig(
                  planeDetection: PlaneDetection.horizontal,
                  showDebugPlanes: true,
                ),
                onCreated: _onArCreated,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black.withValues(alpha: 0.85),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: ArObjectType.values
                      .where((t) => t != ArObjectType.model)
                      .map((type) {
                        final isSelected = type == _selectedType;
                        return GestureDetector(
                          onTap: () => setState(() => _selectedType = type),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.cyanAccent
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              type.name.toUpperCase(),
                              style: TextStyle(
                                color: isSelected ? Colors.black : Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        );
                      })
                      .toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: _colors.entries.map((entry) {
                    final isSelected = entry.value == _selectedColor;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedColor = entry.value),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Color(
                            int.parse(
                                  entry.value.replaceFirst('#', ''),
                                  radix: 16,
                                ) |
                                0xFF000000,
                          ),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSelected
                                ? Colors.white
                                : Colors.transparent,
                            width: 2,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Size', style: TextStyle(color: Colors.white)),
                    Expanded(
                      child: Slider(
                        value: _scale,
                        min: 0.02,
                        max: 0.5,
                        activeColor: Colors.cyanAccent,
                        onChanged: (v) => setState(() => _scale = v),
                      ),
                    ),
                    Text(
                      '${(_scale * 100).toInt()}cm',
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Tap "Place Shape" to place selected primitive.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await _controller?.removeAllNodes();
                          if (!mounted) return;
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete),
                        label: const Text('Clear All'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton.icon(
                        onPressed: _placeShape,
                        icon: const Icon(Icons.add),
                        label: const Text('Place Shape'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Model Viewer Demo ─────────────────────────────────────

class ModelViewerDemo extends StatefulWidget {
  const ModelViewerDemo({super.key});

  @override
  State<ModelViewerDemo> createState() => _ModelViewerDemoState();
}

class _ModelViewerDemoState extends State<ModelViewerDemo> {
  // Use platform-specific model URLs
  static const _demoModelUrlAndroid =
      'https://storage.googleapis.com/ar-answers-in-search-models/static/GiantPanda/model.glb';
  static const _demoModelUrlIOS =
      'https://developer.apple.com/augmented-reality/quick-look/models/biplane/toy_biplane_idle.usdz';

  String get _demoModelUrl {
    return Theme.of(context).platform == TargetPlatform.iOS
        ? _demoModelUrlIOS
        : _demoModelUrlAndroid;
  }

  ArController? _controller;
  bool _modelLoaded = false;
  int _nodeCount = 0;
  String _status = 'Initializing AR...';

  void _onArCreated(ArController controller) {
    _controller = controller;
    controller.onSessionStateChanged = (state) {
      if (!mounted) return;
      setState(() {
        _status = switch (state) {
          ArSessionState.ready => 'Ready. Load model and place it.',
          ArSessionState.tracking => 'Tracking',
          ArSessionState.trackingLost => 'Tracking lost - move slowly',
          ArSessionState.error => 'AR error',
          _ => _status,
        };
      });
    };
    _loadModel();
  }

  Future<void> _loadModel() async {
    if (_controller == null) return;
    setState(() => _status = 'Loading model...');
    try {
      await _controller!.loadModel(
        source: ArSource.url(_demoModelUrl),
        scale: 0.8,
      );
      if (!mounted) return;
      setState(() {
        _modelLoaded = true;
        _status = 'Model loaded. Tap "Place Model".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Load failed: $e');
    }
  }

  Future<void> _placeModel() async {
    if (_controller == null || !_modelLoaded) return;
    try {
      await _controller!.placeModel();
      if (!mounted) return;
      setState(() {
        _nodeCount = _controller!.nodeCount;
        _status = 'Model placed.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _status = 'Place failed: $e');
    }
  }

  Future<void> _clearAll() async {
    await _controller?.removeAllNodes();
    if (!mounted) return;
    setState(() {
      _nodeCount = 0;
      _status = _modelLoaded
          ? 'Cleared. Tap "Place Model" again.'
          : 'Model not loaded yet.';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Model Viewer')),
      body: Column(
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.58,
            child: ClipRect(
              child: ArView(
                config: const ArConfig(
                  planeDetection: PlaneDetection.horizontal,
                  showDebugPlanes: true,
                ),
                onCreated: _onArCreated,
              ),
            ),
          ),
          Container(
            width: double.infinity,
            color: Colors.black.withValues(alpha: 0.85),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(_status, style: const TextStyle(color: Colors.white)),
                const SizedBox(height: 6),
                Text(
                  'Placed models: $_nodeCount',
                  style: const TextStyle(color: Colors.white70),
                ),
                const SizedBox(height: 10),
                const Text(
                  'This device hides overlay controls above AR view. '
                  'Use these external buttons to test model loading and placement.',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loadModel,
                        icon: const Icon(Icons.download),
                        label: const Text('Reload Model'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _clearAll,
                        icon: const Icon(Icons.delete),
                        label: const Text('Clear'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: _modelLoaded ? _placeModel : null,
                        icon: const Icon(Icons.add),
                        label: const Text('Place Model'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyanAccent,
                          foregroundColor: Colors.black,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
