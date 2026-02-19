import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'flutter_ar_easy_platform_interface.dart';

/// An implementation of [FlutterArEasyPlatform] that uses method channels.
class MethodChannelFlutterArEasy extends FlutterArEasyPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('flutter_ar_easy');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
