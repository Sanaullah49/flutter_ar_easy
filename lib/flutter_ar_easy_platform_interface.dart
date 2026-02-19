import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'flutter_ar_easy_method_channel.dart';

abstract class FlutterArEasyPlatform extends PlatformInterface {
  /// Constructs a FlutterArEasyPlatform.
  FlutterArEasyPlatform() : super(token: _token);

  static final Object _token = Object();

  static FlutterArEasyPlatform _instance = MethodChannelFlutterArEasy();

  /// The default instance of [FlutterArEasyPlatform] to use.
  ///
  /// Defaults to [MethodChannelFlutterArEasy].
  static FlutterArEasyPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [FlutterArEasyPlatform] when
  /// they register themselves.
  static set instance(FlutterArEasyPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
