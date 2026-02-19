package com.example.flutter_ar_easy

import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Color
import android.net.Uri
import android.os.Handler
import android.os.HandlerThread
import android.view.PixelCopy
import android.view.View
import android.widget.FrameLayout
import com.google.ar.core.Config
import com.google.ar.core.Frame
import com.google.ar.core.HitResult
import com.google.ar.core.Plane
import com.google.ar.core.Session
import com.google.ar.core.TrackingState
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.ArSceneView
import com.google.ar.sceneform.Node
import com.google.ar.sceneform.math.Quaternion
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.MaterialFactory
import com.google.ar.sceneform.rendering.ModelRenderable
import com.google.ar.sceneform.rendering.ShapeFactory
import io.flutter.FlutterInjector
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.ByteArrayOutputStream
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest

class ArPlatformView(
    private val activity: Activity,
    private val viewId: Int,
    messenger: BinaryMessenger,
    private val creationParams: Map<*, *>
) : PlatformView, MethodChannel.MethodCallHandler {

    private val frameLayout = FrameLayout(activity)
    private var arSceneView: ArSceneView? = null
    private val methodChannel: MethodChannel
    private val eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)

    private val nodes = mutableMapOf<String, Node>()
    private val cachedRemoteUris = mutableMapOf<String, Uri>()
    private val modelCacheDirectory by lazy {
        File(activity.cacheDir, "flutter_ar_easy_models").apply { mkdirs() }
    }

    private var showDebugPlanes = false
    private var planeDetectionMode = 0
    private var isInitialized = false

    init {
        methodChannel = MethodChannel(messenger, "flutter_ar_easy/ar_view_$viewId")
        methodChannel.setMethodCallHandler(this)

        eventChannel = EventChannel(messenger, "flutter_ar_easy/ar_events_$viewId")
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    override fun getView(): View = frameLayout

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "pause" -> pause(result)
            "resume" -> resume(result)
            "prepareModel" -> prepareModel(call, result)
            "placePrimitive" -> placePrimitive(call, result)
            "placeModel" -> placeModel(call, result)
            "placeModelAtScreen" -> placeModelAtScreen(call, result)
            "placeOnTap" -> placeOnTap(call, result)
            "clearModelCache" -> clearModelCache(result)
            "removeNode" -> removeNode(call, result)
            "removeAllNodes" -> removeAllNodes(result)
            "updateNode" -> updateNode(call, result)
            "takeSnapshot" -> takeSnapshot(result)
            "dispose" -> disposeAr(result)
            else -> result.notImplemented()
        }
    }

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
            showDebugPlanes = args["showDebugPlanes"] as? Boolean ?: false
            planeDetectionMode = asInt(args["planeDetection"], 0)

            setupArSceneView()
            isInitialized = true
            result.success(null)
            sendEvent("sessionStateChanged", mapOf("state" to 2))
        } catch (e: Exception) {
            result.error("INIT_ERROR", e.message, null)
        }
    }

    private fun setupArSceneView() {
        arSceneView = ArSceneView(activity).apply {
            layoutParams = FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        }
        frameLayout.addView(arSceneView)

        val sceneView = arSceneView ?: return
        try {
            val session = Session(activity)
            val config = Config(session).apply {
                updateMode = Config.UpdateMode.LATEST_CAMERA_IMAGE
                focusMode = Config.FocusMode.AUTO
                lightEstimationMode = Config.LightEstimationMode.ENVIRONMENTAL_HDR
                planeFindingMode = when (planeDetectionMode) {
                    0 -> Config.PlaneFindingMode.HORIZONTAL
                    1 -> Config.PlaneFindingMode.VERTICAL
                    2 -> Config.PlaneFindingMode.HORIZONTAL_AND_VERTICAL
                    else -> Config.PlaneFindingMode.DISABLED
                }
            }
            session.configure(config)
            sceneView.setupSession(session)
        } catch (e: Exception) {
            sendEvent("sessionStateChanged", mapOf("state" to 5))
            return
        }

        sceneView.scene.addOnUpdateListener {
            val frame = sceneView.arFrame ?: return@addOnUpdateListener

            val isTracking = frame.camera.trackingState == TrackingState.TRACKING
            sendEvent("trackingStateChanged", mapOf("isTracking" to isTracking))

            for (plane in frame.getUpdatedTrackables(Plane::class.java)) {
                if (plane.trackingState != TrackingState.TRACKING) continue
                val pose = plane.centerPose
                sendEvent(
                    "planeDetected",
                    mapOf(
                        "data" to mapOf(
                            "id" to plane.hashCode().toString(),
                            "center" to mapOf(
                                "x" to pose.tx().toDouble(),
                                "y" to pose.ty().toDouble(),
                                "z" to pose.tz().toDouble()
                            ),
                            "width" to plane.extentX.toDouble(),
                            "height" to plane.extentZ.toDouble(),
                            "type" to when (plane.type) {
                                Plane.Type.VERTICAL -> 1
                                else -> 0
                            }
                        )
                    )
                )
            }

            arSceneView?.planeRenderer?.isEnabled = showDebugPlanes
        }

        sceneView.scene.setOnTouchListener { hitTestResult, _ ->
            val tappedNode = hitTestResult.node ?: return@setOnTouchListener false
            val nodeId = nodes.entries.firstOrNull { it.value == tappedNode }?.key
            if (nodeId != null) {
                sendEvent("nodeTapped", mapOf("nodeId" to nodeId))
            }
            false
        }

        sceneView.resume()
    }

    private fun prepareModel(call: MethodCall, result: MethodChannel.Result) {
        if (!isInitialized) {
            result.error("NOT_INITIALIZED", "AR session not initialized", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        val sourceMap = args?.get("source") as? Map<*, *>
        if (sourceMap == null) {
            result.error("INVALID_ARGS", "No source provided", null)
            return
        }

        scope.launch {
            try {
                val uri = resolveModelUri(sourceMap)
                result.success(uri.toString())
            } catch (e: Exception) {
                result.error("MODEL_PREPARE_ERROR", e.message, null)
            }
        }
    }

    private fun placePrimitive(call: MethodCall, result: MethodChannel.Result) {
        if (!isInitialized) {
            result.error("NOT_INITIALIZED", "AR session not initialized", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGS", "No arguments provided", null)
            return
        }

        val id = args["id"] as? String ?: "node_${System.currentTimeMillis()}"
        val objectType = asInt(args["objectType"], 0)
        val position = mapToVector3(
            args["position"] as? Map<*, *>,
            default = Vector3(0f, 0f, -1f)
        )
        val scaleValue = asFloat((args["scale"] as? Map<*, *>)?.get("x"), 0.1f)
        val properties = args["properties"] as? Map<*, *>
        val colorHex = properties?.get("color") as? String ?: "#FF0000"
        val color = try {
            Color.parseColor(colorHex)
        } catch (_: Exception) {
            Color.RED
        }

        MaterialFactory.makeOpaqueWithColor(
            activity,
            com.google.ar.sceneform.rendering.Color(color)
        ).thenAccept { material ->
            val renderable = when (objectType) {
                0 -> ShapeFactory.makeCube(
                    Vector3(scaleValue, scaleValue, scaleValue),
                    Vector3.zero(),
                    material
                )
                1 -> ShapeFactory.makeSphere(scaleValue / 2f, Vector3.zero(), material)
                2 -> ShapeFactory.makeCylinder(
                    scaleValue / 2f,
                    scaleValue,
                    Vector3.zero(),
                    material
                )
                else -> ShapeFactory.makeCube(
                    Vector3(scaleValue, scaleValue, scaleValue),
                    Vector3.zero(),
                    material
                )
            }

            val node = placeRenderableNode(
                id = id,
                renderable = renderable,
                scale = 1f,
                fallbackPosition = position,
                screenX = null,
                screenY = null
            )
            if (node == null) {
                result.error("PLACE_ERROR", "AR scene is not available", null)
                return@thenAccept
            }
            result.success(null)
        }.exceptionally { throwable ->
            result.error(
                "RENDER_ERROR",
                "Failed to create renderable: ${throwable.message}",
                null
            )
            null
        }
    }

    private fun placeModel(call: MethodCall, result: MethodChannel.Result) {
        if (!isInitialized) {
            result.error("NOT_INITIALIZED", "AR session not initialized", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGS", "No arguments provided", null)
            return
        }

        val id = args["id"] as? String ?: "model_${System.currentTimeMillis()}"
        val sourceMap = args["source"] as? Map<*, *>
        if (sourceMap == null) {
            result.error("INVALID_ARGS", "No source provided", null)
            return
        }

        val position = mapToVector3(
            args["position"] as? Map<*, *>,
            default = Vector3(0f, 0f, -1.5f)
        )
        val scale = asFloat((args["scale"] as? Map<*, *>)?.get("x"), 1f)

        loadModelRenderable(sourceMap, onSuccess = { renderable ->
            val node = placeRenderableNode(
                id = id,
                renderable = renderable,
                scale = scale,
                fallbackPosition = position,
                screenX = null,
                screenY = null
            )
            if (node == null) {
                result.error("MODEL_ERROR", "AR scene is not available", null)
                return@loadModelRenderable
            }
            result.success(null)
        }, onError = { error ->
            result.error("MODEL_ERROR", error, null)
        })
    }

    private fun placeModelAtScreen(call: MethodCall, result: MethodChannel.Result) {
        if (!isInitialized) {
            result.error("NOT_INITIALIZED", "AR session not initialized", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGS", "No arguments provided", null)
            return
        }

        val id = args["id"] as? String ?: "model_${System.currentTimeMillis()}"
        val sourceMap = args["source"] as? Map<*, *>
        if (sourceMap == null) {
            result.error("INVALID_ARGS", "No source provided", null)
            return
        }

        val scale = asFloat((args["scale"] as? Map<*, *>)?.get("x"), 1f)
        val screenX = asFloat(args["screenX"], Float.NaN)
        val screenY = asFloat(args["screenY"], Float.NaN)
        if (screenX.isNaN() || screenY.isNaN()) {
            result.error("INVALID_ARGS", "Tap coordinates are required", null)
            return
        }

        loadModelRenderable(sourceMap, onSuccess = { renderable ->
            val node = placeRenderableNode(
                id = id,
                renderable = renderable,
                scale = scale,
                fallbackPosition = Vector3(0f, 0f, -1.5f),
                screenX = screenX,
                screenY = screenY
            )
            if (node == null) {
                result.error("MODEL_ERROR", "AR scene is not available", null)
                return@loadModelRenderable
            }
            result.success(createNodeMap(id, 3, node.localPosition, scale, sourceMap))
        }, onError = { error ->
            result.error("MODEL_ERROR", error, null)
        })
    }

    private fun placeOnTap(call: MethodCall, result: MethodChannel.Result) {
        if (!isInitialized) {
            result.error("NOT_INITIALIZED", "AR session not initialized", null)
            return
        }

        val args = call.arguments as? Map<*, *>
        if (args == null) {
            result.error("INVALID_ARGS", "No arguments provided", null)
            return
        }

        val objectType = asInt(args["objectType"], 0)
        val id = "tap_${System.currentTimeMillis()}"
        val scale = asFloat((args["scale"] as? Map<*, *>)?.get("x"), 0.1f)
        val screenX = args["screenX"]?.let { asFloat(it, 0f) }
        val screenY = args["screenY"]?.let { asFloat(it, 0f) }

        if (objectType == 3) {
            val sourceMap = args["source"] as? Map<*, *>
            if (sourceMap == null) {
                result.error("INVALID_ARGS", "Model source is required", null)
                return
            }

            loadModelRenderable(sourceMap, onSuccess = { renderable ->
                val node = placeRenderableNode(
                    id = id,
                    renderable = renderable,
                    scale = scale,
                    fallbackPosition = Vector3(0f, 0f, -1.5f),
                    screenX = screenX,
                    screenY = screenY
                )
                if (node == null) {
                    result.error("MODEL_ERROR", "AR scene is not available", null)
                    return@loadModelRenderable
                }
                result.success(createNodeMap(id, objectType, node.localPosition, scale, sourceMap))
            }, onError = { error ->
                result.error("MODEL_ERROR", error, null)
            })
            return
        }

        MaterialFactory.makeOpaqueWithColor(
            activity,
            com.google.ar.sceneform.rendering.Color(Color.RED)
        ).thenAccept { material ->
            val renderable = when (objectType) {
                0 -> ShapeFactory.makeCube(
                    Vector3(scale, scale, scale),
                    Vector3.zero(),
                    material
                )
                1 -> ShapeFactory.makeSphere(scale / 2f, Vector3.zero(), material)
                2 -> ShapeFactory.makeCylinder(scale / 2f, scale, Vector3.zero(), material)
                else -> ShapeFactory.makeCube(
                    Vector3(scale, scale, scale),
                    Vector3.zero(),
                    material
                )
            }

            val node = placeRenderableNode(
                id = id,
                renderable = renderable,
                scale = 1f,
                fallbackPosition = Vector3(0f, 0f, -1f),
                screenX = screenX,
                screenY = screenY
            )
            if (node == null) {
                result.error("PLACE_ERROR", "AR scene is not available", null)
                return@thenAccept
            }
            result.success(createNodeMap(id, objectType, node.localPosition, scale, null))
        }.exceptionally { throwable ->
            result.error("PLACE_ERROR", throwable.message, null)
            null
        }
    }

    private fun clearModelCache(result: MethodChannel.Result) {
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    modelCacheDirectory.listFiles()?.forEach { it.delete() }
                }
                cachedRemoteUris.clear()
                result.success(null)
            } catch (e: Exception) {
                result.error("CACHE_ERROR", e.message, null)
            }
        }
    }

    private fun removeNode(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id == null) {
            result.error("INVALID_ARGS", "Node id is required", null)
            return
        }

        val node = nodes.remove(id)
        if (node == null) {
            result.error("NOT_FOUND", "Node not found: $id", null)
            return
        }

        detachNode(node)
        result.success(null)
    }

    private fun removeAllNodes(result: MethodChannel.Result) {
        nodes.values.forEach { detachNode(it) }
        nodes.clear()
        result.success(null)
    }

    private fun updateNode(call: MethodCall, result: MethodChannel.Result) {
        val args = call.arguments as? Map<*, *>
        val id = args?.get("id") as? String

        if (id == null || !nodes.containsKey(id)) {
            result.error("NOT_FOUND", "Node not found: $id", null)
            return
        }

        val node = nodes[id] ?: return
        val posMap = args["position"] as? Map<*, *>
        val scaleMap = args["scale"] as? Map<*, *>
        val rotMap = args["rotation"] as? Map<*, *>

        if (posMap != null) {
            node.localPosition = mapToVector3(posMap, default = Vector3.zero())
        }

        if (scaleMap != null) {
            node.localScale = Vector3(
                asFloat(scaleMap["x"], 1f),
                asFloat(scaleMap["y"], 1f),
                asFloat(scaleMap["z"], 1f)
            )
        }

        if (rotMap != null) {
            node.localRotation = Quaternion.eulerAngles(
                Vector3(
                    asFloat(rotMap["pitch"], 0f),
                    asFloat(rotMap["yaw"], 0f),
                    asFloat(rotMap["roll"], 0f)
                )
            )
        }

        result.success(null)
    }

    private fun pause(result: MethodChannel.Result) {
        try {
            arSceneView?.pause()
            result.success(null)
        } catch (e: Exception) {
            result.error("PAUSE_ERROR", e.message, null)
        }
    }

    private fun resume(result: MethodChannel.Result) {
        try {
            arSceneView?.resume()
            result.success(null)
        } catch (e: Exception) {
            result.error("RESUME_ERROR", e.message, null)
        }
    }

    private fun disposeAr(result: MethodChannel.Result) {
        try {
            cleanup()
            result.success(null)
        } catch (e: Exception) {
            result.error("DISPOSE_ERROR", e.message, null)
        }
    }

    private fun takeSnapshot(result: MethodChannel.Result) {
        val sceneView = arSceneView
        if (sceneView == null) {
            result.error("SNAPSHOT_ERROR", "AR view is not available", null)
            return
        }

        if (sceneView.width <= 0 || sceneView.height <= 0) {
            result.error("SNAPSHOT_ERROR", "AR view has invalid dimensions", null)
            return
        }

        val bitmap = Bitmap.createBitmap(
            sceneView.width,
            sceneView.height,
            Bitmap.Config.ARGB_8888
        )

        val handlerThread = HandlerThread("flutter_ar_easy_pixel_copy").apply { start() }
        val handler = Handler(handlerThread.looper)

        activity.runOnUiThread {
            PixelCopy.request(sceneView, bitmap, { copyResult ->
                try {
                    if (copyResult == PixelCopy.SUCCESS) {
                        val outputStream = ByteArrayOutputStream()
                        bitmap.compress(Bitmap.CompressFormat.PNG, 100, outputStream)
                        result.success(outputStream.toByteArray())
                    } else {
                        result.error(
                            "SNAPSHOT_ERROR",
                            "PixelCopy failed with code: $copyResult",
                            null
                        )
                    }
                } finally {
                    bitmap.recycle()
                    handlerThread.quitSafely()
                }
            }, handler)
        }
    }

    private fun loadModelRenderable(
        sourceMap: Map<*, *>,
        onSuccess: (ModelRenderable) -> Unit,
        onError: (String) -> Unit
    ) {
        scope.launch {
            try {
                val modelUri = resolveModelUri(sourceMap)
                ModelRenderable.builder()
                    .setSource(activity, modelUri)
                    .build()
                    .thenAccept(onSuccess)
                    .exceptionally { throwable: Throwable ->
                        onError("Failed to load model: ${throwable.message}")
                        null
                    }
            } catch (e: Exception) {
                onError(e.message ?: "Failed to resolve model source")
            }
        }
    }

    private fun placeRenderableNode(
        id: String,
        renderable: ModelRenderable,
        scale: Float,
        fallbackPosition: Vector3,
        screenX: Float?,
        screenY: Float?
    ): Node? {
        val sceneView = arSceneView ?: return null
        val hitResult = resolveHitResult(sceneView, screenX, screenY)

        val node = if (hitResult != null) {
            val anchorNode = AnchorNode(hitResult.createAnchor()).apply {
                setParent(sceneView.scene)
            }

            Node().apply {
                this.renderable = renderable
                localScale = Vector3(scale, scale, scale)
                setParent(anchorNode)
            }
        } else {
            Node().apply {
                this.renderable = renderable
                localPosition = fallbackPosition
                localScale = Vector3(scale, scale, scale)
                setParent(sceneView.scene)
            }
        }

        nodes[id] = node
        return node
    }

    private fun resolveHitResult(
        sceneView: ArSceneView,
        screenX: Float?,
        screenY: Float?
    ): HitResult? {
        val frame = sceneView.arFrame ?: return null
        val x = screenX ?: sceneView.width / 2f
        val y = screenY ?: sceneView.height / 2f
        return frame.hitTest(x, y).firstOrNull {
            val trackable = it.trackable
            trackable is Plane && trackable.isPoseInPolygon(it.hitPose)
        }
    }

    private suspend fun resolveModelUri(sourceMap: Map<*, *>): Uri {
        val sourceType = asInt(sourceMap["type"], 0)
        val path = sourceMap["path"] as? String ?: error("Model path is required")
        val cacheRemote = sourceMap["cacheRemoteModel"] as? Boolean ?: true

        return when (sourceType) {
            0 -> {
                val lookupKey = FlutterInjector.instance()
                    .flutterLoader()
                    .getLookupKeyForAsset(path)
                Uri.parse("file:///android_asset/$lookupKey")
            }
            1 -> if (path.startsWith("file://") || path.startsWith("content://")) {
                Uri.parse(path)
            } else {
                Uri.fromFile(File(path))
            }
            2 -> {
                if (cacheRemote) {
                    getCachedModelUri(path)
                } else {
                    Uri.parse(path)
                }
            }
            else -> Uri.parse(path)
        }
    }

    private suspend fun getCachedModelUri(url: String): Uri {
        cachedRemoteUris[url]?.let { cached ->
            val cachedPath = cached.path
            if (cachedPath != null && File(cachedPath).exists()) {
                return cached
            }
        }

        val cachedUri = withContext(Dispatchers.IO) {
            val extension = inferModelExtension(url)
            val hashedName = sha256(url)
            val finalFile = File(modelCacheDirectory, "$hashedName$extension")

            if (finalFile.exists() && finalFile.length() > 0L) {
                return@withContext Uri.fromFile(finalFile)
            }

            val tempFile = File(modelCacheDirectory, "$hashedName$extension.part")
            downloadUrlToFile(url, tempFile)

            if (finalFile.exists()) {
                finalFile.delete()
            }
            if (!tempFile.renameTo(finalFile)) {
                tempFile.copyTo(finalFile, overwrite = true)
                tempFile.delete()
            }

            Uri.fromFile(finalFile)
        }

        cachedRemoteUris[url] = cachedUri
        return cachedUri
    }

    private fun downloadUrlToFile(url: String, output: File) {
        var connection: HttpURLConnection? = null
        try {
            connection = URL(url).openConnection() as HttpURLConnection
            connection.connectTimeout = 15_000
            connection.readTimeout = 30_000
            connection.instanceFollowRedirects = true
            connection.connect()

            if (connection.responseCode !in 200..299) {
                error("Failed to download model (HTTP ${connection.responseCode})")
            }

            connection.inputStream.use { input ->
                FileOutputStream(output).use { fileOutput ->
                    input.copyTo(fileOutput)
                }
            }
        } finally {
            connection?.disconnect()
        }
    }

    private fun inferModelExtension(url: String): String {
        val path = Uri.parse(url).lastPathSegment ?: return ".glb"
        val dotIndex = path.lastIndexOf('.')
        if (dotIndex == -1) return ".glb"

        return when (path.substring(dotIndex).lowercase()) {
            ".glb", ".gltf", ".usdz", ".obj" -> path.substring(dotIndex).lowercase()
            else -> ".glb"
        }
    }

    private fun sha256(input: String): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(input.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun detachNode(node: Node) {
        val parent = node.parent
        node.setParent(null)
        if (parent is AnchorNode) {
            parent.setParent(null)
        }
    }

    private fun createNodeMap(
        id: String,
        objectType: Int,
        position: Vector3,
        scale: Float,
        sourceMap: Map<*, *>?
    ): Map<String, Any?> {
        val source = sourceMap?.let {
            mapOf(
                "type" to asInt(it["type"], 0),
                "path" to (it["path"] as? String ?: "")
            )
        }

        return mapOf(
            "id" to id,
            "objectType" to objectType,
            "source" to source,
            "position" to mapOf(
                "x" to position.x.toDouble(),
                "y" to position.y.toDouble(),
                "z" to position.z.toDouble()
            ),
            "rotation" to mapOf("pitch" to 0.0, "yaw" to 0.0, "roll" to 0.0),
            "scale" to mapOf(
                "x" to scale.toDouble(),
                "y" to scale.toDouble(),
                "z" to scale.toDouble()
            ),
            "properties" to emptyMap<String, Any?>()
        )
    }

    private fun mapToVector3(map: Map<*, *>?, default: Vector3): Vector3 {
        if (map == null) return default
        return Vector3(
            asFloat(map["x"], default.x),
            asFloat(map["y"], default.y),
            asFloat(map["z"], default.z)
        )
    }

    private fun asInt(value: Any?, fallback: Int): Int {
        return when (value) {
            is Int -> value
            is Number -> value.toInt()
            else -> fallback
        }
    }

    private fun asFloat(value: Any?, fallback: Float): Float {
        return when (value) {
            is Float -> value
            is Double -> value.toFloat()
            is Int -> value.toFloat()
            is Number -> value.toFloat()
            else -> fallback
        }
    }

    private fun sendEvent(type: String, data: Map<String, Any?>) {
        activity.runOnUiThread {
            eventSink?.success(
                mutableMapOf<String, Any?>("type" to type).apply {
                    putAll(data)
                }
            )
        }
    }

    private fun cleanup() {
        nodes.values.forEach { detachNode(it) }
        nodes.clear()
        arSceneView?.pause()
        arSceneView?.session?.close()
        arSceneView?.destroy()
        arSceneView = null
        frameLayout.removeAllViews()
        isInitialized = false
    }

    override fun dispose() {
        cleanup()
        scope.cancel()
        methodChannel.setMethodCallHandler(null)
    }
}
