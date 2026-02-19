import Flutter
import ARKit
import UIKit

public class FlutterArEasyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(
      name: "flutter_ar_easy/support",
      binaryMessenger: registrar.messenger()
    )

    let instance = FlutterArEasyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let viewFactory = ArPlatformViewFactory(
      messenger: registrar.messenger(),
      assetLookup: { asset in
        registrar.lookupKey(forAsset: asset)
      }
    )
    registrar.register(viewFactory, withId: "flutter_ar_easy/ar_view")
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isArSupported":
      result(ARWorldTrackingConfiguration.isSupported)
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
