import Flutter
import UIKit

public class FlutterArEasyPlugin: NSObject, FlutterPlugin {
  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "flutter_ar_easy/support", binaryMessenger: registrar.messenger())
    let instance = FlutterArEasyPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "isArSupported":
      // iOS ARKit check (will implement in Phase 3)
      if #available(iOS 11.0, *) {
        result(true)
      } else {
        result(false)
      }
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}