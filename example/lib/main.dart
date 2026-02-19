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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ArView(
            config: const ArConfig(
              planeDetection: PlaneDetection.horizontal,
              showDebugPlanes: true,
              lightEstimation: true,
            ),
            onCreated: _onArCreated,
          ),

          // Top status bar
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.7),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      _status,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                    ),
                  ),
                  Text(
                    '📐 $_planeCount  🧊 $_nodeCount',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),

          // Bottom controls
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FloatingActionButton(
                  heroTag: 'clear',
                  onPressed: _clearAll,
                  backgroundColor: Colors.redAccent,
                  child: const Icon(Icons.delete),
                ),
                const SizedBox(width: 32),
                FloatingActionButton.large(
                  heroTag: 'place',
                  onPressed: _placeCube,
                  backgroundColor: Colors.cyanAccent,
                  child: const Icon(Icons.add, color: Colors.black),
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
      body: Stack(
        children: [
          ArView(
            config: const ArConfig(
              planeDetection: PlaneDetection.horizontal,
              showDebugPlanes: true,
            ),
            onCreated: _onArCreated,
          ),

          // Back button
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),

          // Bottom controls panel
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.85),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(24),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Shape selector
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
                                  color: isSelected
                                      ? Colors.black
                                      : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          );
                        })
                        .toList(),
                  ),

                  const SizedBox(height: 16),

                  // Color selector
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: _colors.entries.map((entry) {
                      final isSelected = entry.value == _selectedColor;
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedColor = entry.value),
                        child: Container(
                          width: 36,
                          height: 36,
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
                              width: 3,
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  const SizedBox(height: 16),

                  // Scale slider
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

                  const SizedBox(height: 16),

                  // Action buttons
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
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton.icon(
                          onPressed: _placeShape,
                          icon: const Icon(Icons.add),
                          label: const Text('Place Shape'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.cyanAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                        ),
                      ),
                    ],
                  ),

                  SizedBox(height: MediaQuery.of(context).padding.bottom),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Model Viewer Demo ─────────────────────────────────────

class ModelViewerDemo extends StatelessWidget {
  const ModelViewerDemo({super.key});

  static const _demoModelUrl =
      'https://storage.googleapis.com/ar-answers-in-search-models/static/GiantPanda/model.glb';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          ArModelViewer(
            modelPath: _demoModelUrl,
            sourceType: ArSourceType.url,
            enableTapToPlace: true,
            initialScale: 0.8,
            showDebugPlanes: true,
            onModelPlaced: (_) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Model placed successfully')),
              );
            },
            onError: (error) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text('Error: $error')));
            },
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            left: 16,
            child: CircleAvatar(
              backgroundColor: Colors.black54,
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.pop(context),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
