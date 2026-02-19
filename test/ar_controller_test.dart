import 'package:flutter/services.dart';
import 'package:flutter_ar_easy/flutter_ar_easy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const viewId = 7;
  const viewChannel = MethodChannel('flutter_ar_easy/ar_view_$viewId');
  const eventChannel = MethodChannel('flutter_ar_easy/ar_events_$viewId');

  final recordedCalls = <MethodCall>[];

  setUp(() {
    recordedCalls.clear();

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventChannel, (call) async {
          if (call.method == 'listen' || call.method == 'cancel') {
            return null;
          }
          return null;
        });

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(viewChannel, (call) async {
          recordedCalls.add(call);

          if (call.method == 'placeModelAtScreen') {
            return {
              'id': 'node_screen',
              'objectType': ArObjectType.model.index,
              'position': {'x': 0.0, 'y': 0.0, 'z': -1.0},
              'rotation': {'pitch': 0.0, 'yaw': 0.0, 'roll': 0.0},
              'scale': {'x': 1.5, 'y': 1.5, 'z': 1.5},
              'source': {
                'type': ArSourceType.url.index,
                'path': 'https://example.com/chair.glb',
              },
              'properties': <String, dynamic>{},
            };
          }

          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(viewChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(eventChannel, null);
  });

  test(
    'loadModel preloads source and placeModel uses loaded defaults',
    () async {
      final controller = ArController.create(viewId);
      await controller.initialize(const ArConfig());

      await controller.loadModel(
        source: const ArSource.url('https://example.com/chair.glb'),
        scale: 1.5,
      );

      final node = await controller.placeModel();

      final prepareCall = recordedCalls.firstWhere(
        (call) => call.method == 'prepareModel',
      );
      final prepareArgs = prepareCall.arguments as Map<dynamic, dynamic>;
      final preparedSource = prepareArgs['source'] as Map<dynamic, dynamic>;
      expect(preparedSource['path'], 'https://example.com/chair.glb');
      expect(preparedSource['cacheRemoteModel'], isTrue);

      final placeCall = recordedCalls.firstWhere(
        (call) => call.method == 'placeModel',
      );
      final placeArgs = placeCall.arguments as Map<dynamic, dynamic>;
      final placedSource = placeArgs['source'] as Map<dynamic, dynamic>;
      final placedScale = placeArgs['scale'] as Map<dynamic, dynamic>;
      expect(placedSource['path'], 'https://example.com/chair.glb');
      expect(placedScale['x'], 1.5);
      expect(node.source?.path, 'https://example.com/chair.glb');

      await controller.dispose();
    },
  );

  test('placeModel throws when no source is provided or preloaded', () async {
    final controller = ArController.create(viewId + 1);

    const secondViewChannel = MethodChannel('flutter_ar_easy/ar_view_8');
    const secondEventChannel = MethodChannel('flutter_ar_easy/ar_events_8');

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secondEventChannel, (call) async => null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secondViewChannel, (call) async => null);

    await controller.initialize(const ArConfig());

    await expectLater(
      () => controller.placeModel(),
      throwsA(isA<ArModelException>()),
    );

    await controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secondViewChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secondEventChannel, null);
  });

  test('placeModelAtScreenPosition returns placed node from native', () async {
    final controller = ArController.create(viewId);
    await controller.initialize(const ArConfig());
    await controller.loadModel(
      source: const ArSource.url('https://example.com/chair.glb'),
      scale: 1.5,
    );

    final node = await controller.placeModelAtScreenPosition(
      screenX: 100,
      screenY: 200,
    );

    expect(node.id, 'node_screen');
    expect(node.objectType, ArObjectType.model);
    expect(node.source?.path, 'https://example.com/chair.glb');

    final screenPlaceCall = recordedCalls.firstWhere(
      (call) => call.method == 'placeModelAtScreen',
    );
    final args = screenPlaceCall.arguments as Map<dynamic, dynamic>;
    expect(args['screenX'], 100.0);
    expect(args['screenY'], 200.0);

    await controller.dispose();
  });

  test('clearModelCache invokes native channel', () async {
    final controller = ArController.create(viewId);
    await controller.initialize(const ArConfig());

    await controller.clearModelCache();

    expect(
      recordedCalls.any((call) => call.method == 'clearModelCache'),
      isTrue,
    );

    await controller.dispose();
  });
}
