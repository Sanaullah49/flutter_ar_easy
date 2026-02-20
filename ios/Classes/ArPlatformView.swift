import ARKit
import AVFoundation
import CryptoKit
import Flutter
import Foundation
import SceneKit
import UIKit

private enum ArPlatformViewError: LocalizedError {
  case invalidArguments(String)
  case unsupportedModelFormat(String)
  case assetNotFound(String)
  case fileNotFound(String)
  case invalidUrl(String)
  case modelHasNoContent
  case downloadFailed(String)

  var errorDescription: String? {
    switch self {
    case .invalidArguments(let message):
      return message
    case .unsupportedModelFormat(let ext):
      return "Model format .\(ext) is not supported on iOS yet. Use USDZ."
    case .assetNotFound(let path):
      return "Asset not found: \(path)"
    case .fileNotFound(let path):
      return "File not found: \(path)"
    case .invalidUrl(let url):
      return "Invalid URL: \(url)"
    case .modelHasNoContent:
      return "Model file loaded but no scene content was found."
    case .downloadFailed(let message):
      return "Failed to download model: \(message)"
    }
  }
}

final class ArPlatformView: NSObject, FlutterPlatformView {
  private let containerView: UIView
  private let arView: ARSCNView
  private let assetLookup: (String) -> String
  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var eventSink: FlutterEventSink?
  private var isInitialized = false
  private var showDebugPlanes = false
  private var planeDetectionMode = 0
  private var lightEstimation = true
  private var planeNodes: [UUID: SCNNode] = [:]
  private var nodes: [String: SCNNode] = [:]
  private var cachedRemoteFiles: [String: URL] = [:]
  private var activeConfig: ARWorldTrackingConfiguration?

  private let supportedModelExtensions: Set<String> = ["usdz", "scn", "dae", "obj", "glb", "gltf"]

  init(
    frame: CGRect,
    viewId: Int64,
    messenger: FlutterBinaryMessenger,
    creationParams: [String: Any],
    assetLookup: @escaping (String) -> String
  ) {
    self.assetLookup = assetLookup
    containerView = UIView(frame: frame)
    arView = ARSCNView(frame: frame)
    methodChannel = FlutterMethodChannel(
      name: "flutter_ar_easy/ar_view_\(viewId)",
      binaryMessenger: messenger
    )
    eventChannel = FlutterEventChannel(
      name: "flutter_ar_easy/ar_events_\(viewId)",
      binaryMessenger: messenger
    )

    super.init()

    setupView(frame: frame)
    methodChannel.setMethodCallHandler(handleMethodCall)
    eventChannel.setStreamHandler(self)
  }

  deinit {
    cleanup()
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  func view() -> UIView {
    containerView
  }

  private func setupView(frame: CGRect) {
    arView.frame = frame
    arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    arView.scene = SCNScene()
    arView.delegate = self
    arView.session.delegate = self
    containerView.addSubview(arView)

    let tapRecognizer = UITapGestureRecognizer(
      target: self,
      action: #selector(handleSceneTap(_:))
    )
    arView.addGestureRecognizer(tapRecognizer)
  }

  private func handleMethodCall(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    switch call.method {
    case "initialize":
      initialize(call: call, result: result)
    case "pause":
      pause(result: result)
    case "resume":
      resume(result: result)
    case "prepareModel":
      prepareModel(call: call, result: result)
    case "placePrimitive":
      placePrimitive(call: call, result: result)
    case "placeModel":
      placeModel(call: call, result: result)
    case "placeModelAtScreen":
      placeModelAtScreen(call: call, result: result)
    case "placeOnTap":
      placeOnTap(call: call, result: result)
    case "clearModelCache":
      clearModelCache(result: result)
    case "removeNode":
      removeNode(call: call, result: result)
    case "removeAllNodes":
      removeAllNodes(result: result)
    case "updateNode":
      updateNode(call: call, result: result)
    case "takeSnapshot":
      takeSnapshot(result: result)
    case "dispose":
      dispose(result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func initialize(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard ARWorldTrackingConfiguration.isSupported else {
      result(
        FlutterError(
          code: "AR_NOT_SUPPORTED",
          message: "ARKit is not supported on this device",
          details: nil
        )
      )
      return
    }

    let args = call.arguments as? [String: Any] ?? [:]
    ensureCameraAccess { granted in
      guard granted else {
        result(
          FlutterError(
            code: "PERMISSION_DENIED",
            message: "Camera permission is required. Grant access and open AR again.",
            details: nil
          )
        )
        self.sendEvent(type: "sessionStateChanged", data: ["state": 5])
        return
      }

      self.startSession(with: args, result: result)
    }
  }

  private func startSession(with args: [String: Any], result: @escaping FlutterResult) {
    showDebugPlanes = boolValue(args["showDebugPlanes"], fallback: false)
    planeDetectionMode = intValue(args["planeDetection"], fallback: 0)
    lightEstimation = boolValue(args["lightEstimation"], fallback: true)

    let config = ARWorldTrackingConfiguration()
    config.planeDetection = planeDetectionOptions(for: planeDetectionMode)
    config.isLightEstimationEnabled = lightEstimation
    activeConfig = config

    arView.debugOptions = showDebugPlanes
      ? [.showFeaturePoints, .showWorldOrigin]
      : []

    arView.session.run(config, options: [.resetTracking, .removeExistingAnchors])
    isInitialized = true
    result(nil)
    sendEvent(type: "sessionStateChanged", data: ["state": 2])
  }

  private func pause(result: @escaping FlutterResult) {
    arView.session.pause()
    result(nil)
  }

  private func resume(result: @escaping FlutterResult) {
    guard let config = activeConfig else {
      result(
        FlutterError(
          code: "NOT_INITIALIZED",
          message: "AR session is not initialized",
          details: nil
        )
      )
      return
    }

    arView.session.run(config)
    result(nil)
  }

  private func prepareModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard guardInitialized(result: result) else { return }

    guard
      let args = call.arguments as? [String: Any],
      let source = args["source"] as? [String: Any]
    else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No model source provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    resolveModelURL(source: source) { resolveResult in
      switch resolveResult {
      case .success(let url):
        result(url.absoluteString)
      case .failure(let error):
        result(self.flutterError(code: "MODEL_PREPARE_ERROR", error: error))
      }
    }
  }

  private func placePrimitive(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard guardInitialized(result: result) else { return }

    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No arguments provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    let id = stringValue(args["id"], fallback: "node_\(Date().timeIntervalSince1970)")
    let objectType = intValue(args["objectType"], fallback: 0)
    let positionMap = args["position"] as? [String: Any]
    let scaleMap = args["scale"] as? [String: Any]
    let properties = args["properties"] as? [String: Any]
    let color = parseColor(properties?["color"] as? String)
    let scale = vector(from: scaleMap, fallback: SCNVector3(0.1, 0.1, 0.1))

    let node = makePrimitiveNode(objectType: objectType, scale: scale, color: color)
    node.name = id

    placeNode(
      id: id,
      node: node,
      source: nil,
      fallbackOffset: vector(from: positionMap, fallback: SCNVector3(0, 0, -1)),
      screenPoint: nil
    )

    result(nil)
  }

  private func placeModel(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard guardInitialized(result: result) else { return }

    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No arguments provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    guard let source = args["source"] as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No model source provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    let id = stringValue(args["id"], fallback: "model_\(Date().timeIntervalSince1970)")
    let fallbackOffset = vector(
      from: args["position"] as? [String: Any],
      fallback: SCNVector3(0, 0, -1.5)
    )
    let scale = vector(from: args["scale"] as? [String: Any], fallback: SCNVector3(1, 1, 1))

    loadModelNode(from: source) { loadResult in
      switch loadResult {
      case .success(let modelNode):
        modelNode.scale = scale
        modelNode.name = id
        self.placeNode(
          id: id,
          node: modelNode,
          source: source,
          fallbackOffset: fallbackOffset,
          screenPoint: nil
        )
        result(nil)
      case .failure(let error):
        result(self.flutterError(code: "MODEL_ERROR", error: error))
      }
    }
  }

  private func placeModelAtScreen(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard guardInitialized(result: result) else { return }

    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No arguments provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    guard let source = args["source"] as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No model source provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    let screenX = doubleValue(args["screenX"], fallback: .nan)
    let screenY = doubleValue(args["screenY"], fallback: .nan)
    guard !screenX.isNaN, !screenY.isNaN else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("Tap coordinates are required").localizedDescription,
          details: nil
        )
      )
      return
    }

    let id = stringValue(args["id"], fallback: "model_\(Date().timeIntervalSince1970)")
    let scale = vector(from: args["scale"] as? [String: Any], fallback: SCNVector3(1, 1, 1))
    let screenPoint = CGPoint(x: screenX, y: screenY)

    loadModelNode(from: source) { loadResult in
      switch loadResult {
      case .success(let modelNode):
        modelNode.scale = scale
        modelNode.name = id
        let placedNode = self.placeNode(
          id: id,
          node: modelNode,
          source: source,
          fallbackOffset: SCNVector3(0, 0, -1.5),
          screenPoint: screenPoint
        )
        result(self.createNodeMap(
          id: id,
          objectType: 3,
          node: placedNode,
          source: source
        ))
      case .failure(let error):
        result(self.flutterError(code: "MODEL_ERROR", error: error))
      }
    }
  }

  private func placeOnTap(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard guardInitialized(result: result) else { return }

    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No arguments provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    let objectType = intValue(args["objectType"], fallback: 0)
    let id = "tap_\(Date().timeIntervalSince1970)"
    let scale = vector(from: args["scale"] as? [String: Any], fallback: SCNVector3(0.1, 0.1, 0.1))
    let screenX = args["screenX"] != nil ? doubleValue(args["screenX"], fallback: .nan) : nil
    let screenY = args["screenY"] != nil ? doubleValue(args["screenY"], fallback: .nan) : nil
    let screenPoint: CGPoint? = {
      guard
        let x = screenX,
        let y = screenY,
        !x.isNaN,
        !y.isNaN
      else {
        return nil
      }
      return CGPoint(x: x, y: y)
    }()

    if objectType == 3 {
      guard let source = args["source"] as? [String: Any] else {
        result(
          FlutterError(
            code: "INVALID_ARGS",
            message: ArPlatformViewError.invalidArguments("Model source is required").localizedDescription,
            details: nil
          )
        )
        return
      }

      loadModelNode(from: source) { loadResult in
        switch loadResult {
        case .success(let modelNode):
          modelNode.name = id
          modelNode.scale = scale
          let placedNode = self.placeNode(
            id: id,
            node: modelNode,
            source: source,
            fallbackOffset: SCNVector3(0, 0, -1.5),
            screenPoint: screenPoint
          )
          result(self.createNodeMap(
            id: id,
            objectType: 3,
            node: placedNode,
            source: source
          ))
        case .failure(let error):
          result(self.flutterError(code: "MODEL_ERROR", error: error))
        }
      }

      return
    }

    let primitiveNode = makePrimitiveNode(objectType: objectType, scale: scale, color: .red)
    primitiveNode.name = id
    let placedNode = placeNode(
      id: id,
      node: primitiveNode,
      source: nil,
      fallbackOffset: SCNVector3(0, 0, -1.0),
      screenPoint: screenPoint
    )

    result(createNodeMap(id: id, objectType: objectType, node: placedNode, source: nil))
  }

  private func clearModelCache(result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .utility).async {
      do {
        let cacheDirectory = self.modelCacheDirectoryURL()
        let fileManager = FileManager.default

        if fileManager.fileExists(atPath: cacheDirectory.path) {
          let files = try fileManager.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
          )

          for file in files {
            try fileManager.removeItem(at: file)
          }
        }

        self.cachedRemoteFiles.removeAll()

        DispatchQueue.main.async {
          result(nil)
        }
      } catch {
        DispatchQueue.main.async {
          result(self.flutterError(code: "CACHE_ERROR", error: error))
        }
      }
    }
  }

  private func removeNode(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments as? [String: Any] else {
      result(
        FlutterError(
          code: "INVALID_ARGS",
          message: ArPlatformViewError.invalidArguments("No arguments provided").localizedDescription,
          details: nil
        )
      )
      return
    }

    let id = stringValue(args["id"], fallback: "")
    guard let node = nodes[id] else {
      result(
        FlutterError(
          code: "NOT_FOUND",
          message: "Node not found: \(id)",
          details: nil
        )
      )
      return
    }

    node.removeFromParentNode()
    nodes.removeValue(forKey: id)
    result(nil)
  }

  private func removeAllNodes(result: @escaping FlutterResult) {
    for (_, node) in nodes {
      node.removeFromParentNode()
    }
    nodes.removeAll()
    result(nil)
  }

  private func updateNode(call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard
      let args = call.arguments as? [String: Any],
      let id = args["id"] as? String,
      let node = nodes[id]
    else {
      result(
        FlutterError(
          code: "NOT_FOUND",
          message: "Node not found",
          details: nil
        )
      )
      return
    }

    if let positionMap = args["position"] as? [String: Any] {
      node.position = vector(from: positionMap, fallback: node.position)
    }

    if let scaleMap = args["scale"] as? [String: Any] {
      node.scale = vector(from: scaleMap, fallback: node.scale)
    }

    if let rotationMap = args["rotation"] as? [String: Any] {
      let pitch = floatValue(rotationMap["pitch"], fallback: 0)
      let yaw = floatValue(rotationMap["yaw"], fallback: 0)
      let roll = floatValue(rotationMap["roll"], fallback: 0)
      node.eulerAngles = SCNVector3(
        pitch * .pi / 180,
        yaw * .pi / 180,
        roll * .pi / 180
      )
    }

    result(nil)
  }

  private func takeSnapshot(result: @escaping FlutterResult) {
    let image = arView.snapshot()
    guard let data = image.pngData() else {
      result(nil)
      return
    }

    result([UInt8](data))
  }

  private func dispose(result: @escaping FlutterResult) {
    cleanup()
    result(nil)
  }

  private func cleanup() {
    for (_, node) in nodes {
      node.removeFromParentNode()
    }

    nodes.removeAll()
    planeNodes.removeAll()
    cachedRemoteFiles.removeAll()
    eventSink = nil
    arView.session.pause()
    arView.delegate = nil
    arView.session.delegate = nil
    isInitialized = false
  }

  private func guardInitialized(result: @escaping FlutterResult) -> Bool {
    if isInitialized {
      return true
    }

    result(
      FlutterError(
        code: "NOT_INITIALIZED",
        message: "AR session not initialized",
        details: nil
      )
    )
    return false
  }

  private func ensureCameraAccess(_ completion: @escaping (Bool) -> Void) {
    let status = AVCaptureDevice.authorizationStatus(for: .video)
    switch status {
    case .authorized:
      completion(true)
    case .notDetermined:
      AVCaptureDevice.requestAccess(for: .video) { granted in
        DispatchQueue.main.async {
          completion(granted)
        }
      }
    case .denied, .restricted:
      completion(false)
    @unknown default:
      completion(false)
    }
  }

  private func loadModelNode(
    from source: [String: Any],
    completion: @escaping (Result<SCNNode, Error>) -> Void
  ) {
    resolveModelURL(source: source) { resolveResult in
      switch resolveResult {
      case .success(let url):
        do {
          let modelNode = try self.createModelNode(from: url)
          completion(.success(modelNode))
        } catch {
          completion(.failure(error))
        }
      case .failure(let error):
        completion(.failure(error))
      }
    }
  }

  private func createModelNode(from url: URL) throws -> SCNNode {
    let ext = url.pathExtension.lowercased()
    guard supportedModelExtensions.contains(ext) else {
      throw ArPlatformViewError.unsupportedModelFormat(ext)
    }

    // Handle GLB/GLTF by attempting to load as SCN-compatible DAE first
    if ext == "glb" || ext == "gltf" {
      // Try loading via SCNScene (some GLB files work if they're simple)
      do {
        let scene = try SCNScene(url: url, options: [
          .checkConsistency: true,
          .flattenScene: false,
        ])
        let container = SCNNode()
        for child in scene.rootNode.childNodes {
          container.addChildNode(child.clone())
        }

        guard !container.childNodes.isEmpty else {
          throw ArPlatformViewError.modelHasNoContent
        }
        return container
      } catch {
        // If loading fails, throw informative error
        throw ArPlatformViewError.unsupportedModelFormat(
          "\(ext) - SceneKit cannot load this GLB file. Convert to USDZ for iOS. Error: \(error.localizedDescription)"
        )
      }
    }

    // Standard loading for USDZ/SCN/DAE/OBJ
    let scene = try SCNScene(url: url, options: nil)
    let container = SCNNode()

    for child in scene.rootNode.childNodes {
      container.addChildNode(child.clone())
    }

    guard !container.childNodes.isEmpty else {
      throw ArPlatformViewError.modelHasNoContent
    }

    return container
  }

  private func makePrimitiveNode(
    objectType: Int,
    scale: SCNVector3,
    color: UIColor
  ) -> SCNNode {
    let geometry: SCNGeometry
    switch objectType {
    case 1:
      geometry = SCNSphere(radius: CGFloat(scale.x / 2))
    case 2:
      geometry = SCNCylinder(radius: CGFloat(scale.x / 2), height: CGFloat(scale.y))
    default:
      geometry = SCNBox(
        width: CGFloat(scale.x),
        height: CGFloat(scale.y),
        length: CGFloat(scale.z),
        chamferRadius: 0
      )
    }

    geometry.firstMaterial?.diffuse.contents = color
    return SCNNode(geometry: geometry)
  }

  @discardableResult
  private func placeNode(
    id: String,
    node: SCNNode,
    source: [String: Any]?,
    fallbackOffset: SCNVector3,
    screenPoint: CGPoint?
  ) -> SCNNode {
    if let hitTransform = hitTestTransform(at: screenPoint) {
      node.simdTransform = hitTransform
    } else {
      node.position = worldPositionFromCamera(offset: fallbackOffset)
    }

    arView.scene.rootNode.addChildNode(node)
    nodes[id] = node
    return node
  }

  private func hitTestTransform(at screenPoint: CGPoint?) -> simd_float4x4? {
    let targetPoint = screenPoint ?? CGPoint(
      x: arView.bounds.midX,
      y: arView.bounds.midY
    )

    let results = arView.hitTest(
      targetPoint,
      types: [
        .existingPlaneUsingExtent,
        .estimatedHorizontalPlane,
        .estimatedVerticalPlane,
      ]
    )

    return results.first?.worldTransform
  }

  private func worldPositionFromCamera(offset: SCNVector3) -> SCNVector3 {
    guard let currentFrame = arView.session.currentFrame else {
      return offset
    }

    let cameraTransform = currentFrame.camera.transform
    let translation = simd_float4(offset.x, offset.y, offset.z, 1.0)
    let world = simd_mul(cameraTransform, translation)
    return SCNVector3(world.x, world.y, world.z)
  }

  private func resolveModelURL(
    source: [String: Any],
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    let sourceType = intValue(source["type"], fallback: 0)
    let path = stringValue(source["path"], fallback: "")
    let cacheRemote = boolValue(source["cacheRemoteModel"], fallback: true)

    switch sourceType {
    case 0:
      if let assetURL = resolveAssetURL(path: path) {
        completion(.success(assetURL))
      } else {
        completion(.failure(ArPlatformViewError.assetNotFound(path)))
      }
    case 1:
      let fileURL: URL
      if path.hasPrefix("file://") {
        guard let url = URL(string: path) else {
          completion(.failure(ArPlatformViewError.invalidUrl(path)))
          return
        }
        fileURL = url
      } else {
        fileURL = URL(fileURLWithPath: path)
      }

      guard FileManager.default.fileExists(atPath: fileURL.path) else {
        completion(.failure(ArPlatformViewError.fileNotFound(fileURL.path)))
        return
      }

      completion(.success(fileURL))
    case 2:
      guard let remoteURL = URL(string: path) else {
        completion(.failure(ArPlatformViewError.invalidUrl(path)))
        return
      }

      if cacheRemote {
        // Check in-memory cache first
        if let cached = cachedRemoteFiles[path] {
          do {
            let attrs = try FileManager.default.attributesOfItem(atPath: cached.path)
            if let size = attrs[.size] as? UInt64, size > 0 {
              completion(.success(cached))
              return
            }
          } catch {
            // File invalid - remove from memory cache
            cachedRemoteFiles.removeValue(forKey: path)
          }
        }

        // Check on-disk cache
        let cacheFile = cachedFileURL(for: remoteURL)
        do {
          let attrs = try FileManager.default.attributesOfItem(atPath: cacheFile.path)
          if let size = attrs[.size] as? UInt64, size > 0 {
            cachedRemoteFiles[path] = cacheFile
            completion(.success(cacheFile))
            return
          }
        } catch {
          // Not cached on disk - need to download
        }

        // Download and cache
        downloadRemoteModel(from: remoteURL, to: cacheFile) { downloadResult in
          switch downloadResult {
          case .success(let url):
            self.cachedRemoteFiles[path] = url
            completion(.success(url))
          case .failure(let error):
            completion(.failure(error))
          }
        }
      } else {
        // No caching - download to temp
        let tempFile = temporaryFileURL(for: remoteURL)
        downloadRemoteModel(from: remoteURL, to: tempFile, completion: completion)
      }
    default:
      completion(.failure(ArPlatformViewError.invalidArguments("Unsupported source type")))
    }
  }

  private func resolveAssetURL(path: String) -> URL? {
    let lookupKey = assetLookup(path)
    let fileManager = FileManager.default
    let directPath = "\(Bundle.main.bundlePath)/\(lookupKey)"
    if fileManager.fileExists(atPath: directPath) {
      return URL(fileURLWithPath: directPath)
    }

    let appFrameworkAssetPath =
      "\(Bundle.main.bundlePath)/Frameworks/App.framework/flutter_assets/\(path)"
    if fileManager.fileExists(atPath: appFrameworkAssetPath) {
      return URL(fileURLWithPath: appFrameworkAssetPath)
    }

    let flutterAssetsPath = "\(Bundle.main.bundlePath)/flutter_assets/\(path)"
    if fileManager.fileExists(atPath: flutterAssetsPath) {
      return URL(fileURLWithPath: flutterAssetsPath)
    }

    if let bundlePath = Bundle.main.path(forResource: lookupKey, ofType: nil) {
      return URL(fileURLWithPath: bundlePath)
    }

    return nil
  }

  private func downloadRemoteModel(
    from remoteURL: URL,
    to destinationURL: URL,
    completion: @escaping (Result<URL, Error>) -> Void
  ) {
    URLSession.shared.downloadTask(with: remoteURL) { tempURL, _, error in
      if let error {
        completion(.failure(ArPlatformViewError.downloadFailed(error.localizedDescription)))
        return
      }

      guard let tempURL else {
        completion(.failure(ArPlatformViewError.downloadFailed("No downloaded file found")))
        return
      }

      do {
        try FileManager.default.createDirectory(
          at: destinationURL.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )

        if FileManager.default.fileExists(atPath: destinationURL.path) {
          try FileManager.default.removeItem(at: destinationURL)
        }

        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        completion(.success(destinationURL))
      } catch {
        completion(.failure(ArPlatformViewError.downloadFailed(error.localizedDescription)))
      }
    }.resume()
  }

  private func cachedFileURL(for remoteURL: URL) -> URL {
    let ext = safeModelExtension(from: remoteURL)
    let hash = sha256(remoteURL.absoluteString)
    return modelCacheDirectoryURL().appendingPathComponent("\(hash)\(ext)")
  }

  private func temporaryFileURL(for remoteURL: URL) -> URL {
    let ext = safeModelExtension(from: remoteURL)
    let fileName = "flutter_ar_easy_tmp_\(UUID().uuidString)\(ext)"
    return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
  }

  private func safeModelExtension(from remoteURL: URL) -> String {
    let ext = remoteURL.pathExtension.lowercased()
    if supportedModelExtensions.contains(ext) {
      return ".\(ext)"
    }
    return ".usdz"
  }

  private func modelCacheDirectoryURL() -> URL {
    let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
    return caches.appendingPathComponent("flutter_ar_easy_models", isDirectory: true)
  }

  private func sha256(_ input: String) -> String {
    let digest = SHA256.hash(data: Data(input.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
  }

  private func createNodeMap(
    id: String,
    objectType: Int,
    node: SCNNode,
    source: [String: Any]?
  ) -> [String: Any] {
    let rotation = node.eulerAngles
    let scale = node.scale
    let position = node.position

    return [
      "id": id,
      "objectType": objectType,
      "source": source ?? NSNull(),
      "position": [
        "x": Double(position.x),
        "y": Double(position.y),
        "z": Double(position.z),
      ],
      "rotation": [
        "pitch": Double(rotation.x * 180 / .pi),
        "yaw": Double(rotation.y * 180 / .pi),
        "roll": Double(rotation.z * 180 / .pi),
      ],
      "scale": [
        "x": Double(scale.x),
        "y": Double(scale.y),
        "z": Double(scale.z),
      ],
      "properties": [:] as [String: Any],
    ]
  }

  @objc private func handleSceneTap(_ recognizer: UITapGestureRecognizer) {
    let point = recognizer.location(in: arView)
    let hits = arView.hitTest(point, options: nil)

    for hit in hits {
      var target: SCNNode? = hit.node
      while let current = target {
        if let id = current.name, nodes[id] != nil {
          sendEvent(type: "nodeTapped", data: ["nodeId": id])
          return
        }
        target = current.parent
      }
    }
  }

  private func sendEvent(type: String, data: [String: Any]) {
    guard let sink = eventSink else { return }
    DispatchQueue.main.async {
      var payload: [String: Any] = ["type": type]
      for (key, value) in data {
        payload[key] = value
      }
      sink(payload)
    }
  }

  private func flutterError(code: String, error: Error) -> FlutterError {
    FlutterError(code: code, message: error.localizedDescription, details: nil)
  }

  private func planeDetectionOptions(for mode: Int) -> ARWorldTrackingConfiguration.PlaneDetection {
    switch mode {
    case 0:
      return [.horizontal]
    case 1:
      return [.vertical]
    case 2:
      return [.horizontal, .vertical]
    default:
      return []
    }
  }

  private func vector(from map: [String: Any]?, fallback: SCNVector3) -> SCNVector3 {
    guard let map else { return fallback }
    return SCNVector3(
      floatValue(map["x"], fallback: fallback.x),
      floatValue(map["y"], fallback: fallback.y),
      floatValue(map["z"], fallback: fallback.z)
    )
  }

  private func intValue(_ value: Any?, fallback: Int) -> Int {
    if let int = value as? Int {
      return int
    }
    if let double = value as? Double {
      return Int(double)
    }
    if let float = value as? Float {
      return Int(float)
    }
    return fallback
  }

  private func doubleValue(_ value: Any?, fallback: Double) -> Double {
    if let double = value as? Double {
      return double
    }
    if let int = value as? Int {
      return Double(int)
    }
    if let float = value as? Float {
      return Double(float)
    }
    return fallback
  }

  private func floatValue(_ value: Any?, fallback: Float) -> Float {
    if let float = value as? Float {
      return float
    }
    if let double = value as? Double {
      return Float(double)
    }
    if let int = value as? Int {
      return Float(int)
    }
    return fallback
  }

  private func boolValue(_ value: Any?, fallback: Bool) -> Bool {
    if let bool = value as? Bool {
      return bool
    }
    return fallback
  }

  private func stringValue(_ value: Any?, fallback: String) -> String {
    if let string = value as? String {
      return string
    }
    return fallback
  }

  private func parseColor(_ hex: String?) -> UIColor {
    guard let hex else { return .red }
    var cleaned = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if cleaned.hasPrefix("#") {
      cleaned.removeFirst()
    }

    guard cleaned.count == 6 || cleaned.count == 8 else {
      return .red
    }

    var value: UInt64 = 0
    guard Scanner(string: cleaned).scanHexInt64(&value) else {
      return .red
    }

    let hasAlpha = cleaned.count == 8
    let alpha: CGFloat
    let red: CGFloat
    let green: CGFloat
    let blue: CGFloat

    if hasAlpha {
      // Format: AARRGGBB
      alpha = CGFloat((value & 0xFF000000) >> 24) / 255
      red = CGFloat((value & 0x00FF0000) >> 16) / 255
      green = CGFloat((value & 0x0000FF00) >> 8) / 255
      blue = CGFloat(value & 0x000000FF) / 255
    } else {
      // Format: RRGGBB
      alpha = 1.0
      red = CGFloat((value & 0xFF0000) >> 16) / 255
      green = CGFloat((value & 0x00FF00) >> 8) / 255
      blue = CGFloat(value & 0x0000FF) / 255
    }

    return UIColor(red: red, green: green, blue: blue, alpha: alpha)
  }
}

extension ArPlatformView: FlutterStreamHandler {
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    eventSink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    eventSink = nil
    return nil
  }
}

extension ArPlatformView: ARSCNViewDelegate {
  func renderer(_ renderer: SCNSceneRenderer, didAdd node: SCNNode, for anchor: ARAnchor) {
    guard let planeAnchor = anchor as? ARPlaneAnchor else { return }

    sendEvent(
      type: "planeDetected",
      data: [
        "data": [
          "id": planeAnchor.identifier.uuidString,
          "center": [
            "x": Double(planeAnchor.center.x),
            "y": Double(planeAnchor.center.y),
            "z": Double(planeAnchor.center.z),
          ],
          "width": Double(planeAnchor.extent.x),
          "height": Double(planeAnchor.extent.z),
          "type": planeAnchor.alignment == .vertical ? 1 : 0,
        ],
      ]
    )

    guard showDebugPlanes else { return }

    let plane = SCNPlane(
      width: CGFloat(planeAnchor.extent.x),
      height: CGFloat(planeAnchor.extent.z)
    )
    plane.firstMaterial?.diffuse.contents = UIColor.yellow.withAlphaComponent(0.25)
    plane.firstMaterial?.isDoubleSided = true

    let planeNode = SCNNode(geometry: plane)
    planeNode.eulerAngles.x = -.pi / 2
    planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
    node.addChildNode(planeNode)
    planeNodes[planeAnchor.identifier] = planeNode
  }

  func renderer(_ renderer: SCNSceneRenderer, didUpdate node: SCNNode, for anchor: ARAnchor) {
    guard
      showDebugPlanes,
      let planeAnchor = anchor as? ARPlaneAnchor,
      let planeNode = planeNodes[planeAnchor.identifier],
      let plane = planeNode.geometry as? SCNPlane
    else {
      return
    }

    plane.width = CGFloat(planeAnchor.extent.x)
    plane.height = CGFloat(planeAnchor.extent.z)
    planeNode.position = SCNVector3(planeAnchor.center.x, 0, planeAnchor.center.z)
  }

  func renderer(_ renderer: SCNSceneRenderer, didRemove node: SCNNode, for anchor: ARAnchor) {
    guard let planeAnchor = anchor as? ARPlaneAnchor else { return }
    planeNodes[planeAnchor.identifier]?.removeFromParentNode()
    planeNodes.removeValue(forKey: planeAnchor.identifier)
  }
}

extension ArPlatformView: ARSessionDelegate {
  func session(_ session: ARSession, cameraDidChangeTrackingState camera: ARCamera) {
    let isTracking: Bool
    switch camera.trackingState {
    case .normal:
      isTracking = true
    case .notAvailable, .limited:
      isTracking = false
    }

    sendEvent(type: "trackingStateChanged", data: ["isTracking": isTracking])
  }

  func session(_ session: ARSession, didFailWithError error: Error) {
    sendEvent(type: "sessionStateChanged", data: ["state": 5])
  }

  func sessionWasInterrupted(_ session: ARSession) {
    sendEvent(type: "trackingStateChanged", data: ["isTracking": false])
  }

  func sessionInterruptionEnded(_ session: ARSession) {
    sendEvent(type: "sessionStateChanged", data: ["state": 2])
  }
}
