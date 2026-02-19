import Flutter
import Foundation

final class ArPlatformViewFactory: NSObject, FlutterPlatformViewFactory {
  private let messenger: FlutterBinaryMessenger
  private let assetLookup: (String) -> String

  init(
    messenger: FlutterBinaryMessenger,
    assetLookup: @escaping (String) -> String
  ) {
    self.messenger = messenger
    self.assetLookup = assetLookup
    super.init()
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    let creationParams = args as? [String: Any] ?? [:]
    return ArPlatformView(
      frame: frame,
      viewId: viewId,
      messenger: messenger,
      creationParams: creationParams,
      assetLookup: assetLookup
    )
  }
}
