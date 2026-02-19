package com.fluttareasy.flutter_ar_easy

import android.app.Activity
import android.graphics.Color
import android.net.Uri
import android.view.View
import android.widget.FrameLayout
import com.google.ar.core.*
import com.google.ar.sceneform.AnchorNode
import com.google.ar.sceneform.ArSceneView
import com.google.ar.sceneform.Node
import com.google.ar.sceneform.Scene
import com.google.ar.sceneform.math.Quaternion
import com.google.ar.sceneform.math.Vector3
import com.google.ar.sceneform.rendering.*
import com.google.ar.sceneform.ux.ArFragment
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView

class ArPlatformView(
    private val activity: Activity,
    private val viewId: Int,
    messenger: BinaryMessenger,
    private val creationParams: Map<*, *>
) : PlatformView, MethodChannel.MethodCallHandler {

    private val frameLayout: FrameLayout = FrameLayout(activity)
    private var arSceneView: ArSceneView? = null
    private val methodChannel: MethodChannel
    private val eventChannel: EventChannel
    private var eventSink: EventChannel.EventSink? = null

    private val nodes = mutableMapOf<String, Node>()
    private var showDebugPlanes: Boolean = false
    private var planeDetectionMode: Int = 0
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
            "placePrimitive" -> placePrimitive(call, result)
            "placeModel" -> placeModel(call, result)
            "removeNode" -> removeNode(call, result)
            "removeAllNodes" -> removeAllNodes(result)
            "updateNode" -> updateNode(call, result)
            "dispose" -> disposeAr(result)
            else -> result.notImplemented()
        }
    }

    // ─── Initialize ──────────────────────────────────────────

    private fun initialize(call: MethodCall, result: MethodChannel.Result) {
        try {
            val args = call.arguments as? Map<*, *> ?: emptyMap<String, Any>()
            showDebugPlanes = args["showDebugPlanes"] as? Boolean ?: false
            planeDetectionMode = args["planeDetection"] as? Int ?: 0

            setupArSceneView()
            isInitialized = true
            result.success(null)

            sendEvent("sessionStateChanged", mapOf("state" to 2)) // ready
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

        // Setup session
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
            sendEvent("sessionStateChanged", mapOf("state" to 5)) // error
            return
        }

        // Setup plane detection listener
        sceneView.scene.addOnUpdateListener { frameTime ->
            val frame = sceneView.arFrame ?: return@addOnUpdateListener

            // Notify tracking state
            val camera = frame.camera
            val isTracking = camera.trackingState == TrackingState.TRACKING
            sendEvent("trackingStateChanged", mapOf("isTracking" to isTracking))

            // Check for new planes
            for (plane in frame.getUpdatedTrackables(Plane::class.java)) {
                if (plane.trackingState == TrackingState.TRACKING) {
                    val pose = plane.centerPose
                    sendEvent("planeDetected", mapOf(
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
                                Plane.Type.HORIZONTAL_UPWARD_FACING -> 0
                                Plane.Type.HORIZONTAL_DOWNWARD_FACING -> 0
                                Plane.Type.VERTICAL -> 1
                                else -> 0
                            }
                        )
                    ))
                }
            }

            // Render debug planes
            if (showDebugPlanes) {
                renderDebugPlanes(frame)
            }
        }

        // Tap listener
        sceneView.scene.setOnTouchListener { hitTestResult, motionEvent ->
            if (hitTestResult.node != null) {
                val nodeId = nodes.entries.find {
                    it.value == hitTestResult.node
                }?.key
                if (nodeId != null) {
                    sendEvent("nodeTapped", mapOf("nodeId" to nodeId))
                }
            }
            false
        }

        sceneView.resume()
    }

    private fun renderDebugPlanes(frame: Frame) {
        // Debug planes are rendered via Sceneform's built-in plane renderer
        arSceneView?.planeRenderer?.isEnabled = showDebugPlanes
    }

    // ─── Place Primitive ─────────────────────────────────────

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
        val objectType = args["objectType"] as? Int ?: 0
        val posMap = args["position"] as? Map<*, *>
        val scaleMap = args["scale"] as? Map<*, *>
        val properties = args["properties"] as? Map<*, *>

        val position = Vector3(
            (posMap?.get("x") as? Double)?.toFloat() ?: 0f,
            (posMap?.get("y") as? Double)?.toFloat() ?: 0f,
            (posMap?.get("z") as? Double)?.toFloat() ?: -1f
        )

        val scaleValue = (scaleMap?.get("x") as? Double)?.toFloat() ?: 0.1f

        // Get color from properties
        val colorHex = properties?.get("color") as? String ?: "#FF0000"
        val color = try {
            Color.parseColor(colorHex)
        } catch (e: Exception) {
            Color.RED
        }

        activity.runOnUiThread {
            try {
                // Create material
                MaterialFactory.makeOpaqueWithColor(
                    activity,
                    com.google.ar.sceneform.rendering.Color(color)
                ).thenAccept { material ->

                    // Create shape based on type
                    val renderable: ModelRenderable = when (objectType) {
                        0 -> ShapeFactory.makeCube(
                            Vector3(scaleValue, scaleValue, scaleValue),
                            Vector3.zero(),
                            material
                        )
                        1 -> ShapeFactory.makeSphere(
                            scaleValue / 2f,
                            Vector3.zero(),
                            material
                        )
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

                    // Try to anchor to a detected plane first
                    val sceneView = arSceneView ?: return@thenAccept
                    val frame = sceneView.arFrame ?: return@thenAccept
                    val session = sceneView.session ?: return@thenAccept

                    // Perform hit test at center of screen
                    val hitResults = frame.hitTest(
                        sceneView.width / 2f,
                        sceneView.height / 2f
                    )

                    val hitResult = hitResults.firstOrNull {
                        val trackable = it.trackable
                        trackable is Plane && trackable.isPoseInPolygon(it.hitPose)
                    }

                    if (hitResult != null) {
                        // Place on detected plane
                        val anchor = hitResult.createAnchor()
                        val anchorNode = AnchorNode(anchor).apply {
                            setParent(sceneView.scene)
                        }

                        val node = Node().apply {
                            this.renderable = renderable
                            localScale = Vector3(1f, 1f, 1f)
                            setParent(anchorNode)
                        }

                        nodes[id] = anchorNode
                    } else {
                        // Place in front of camera
                        val node = Node().apply {
                            this.renderable = renderable
                            localPosition = position
                            setParent(sceneView.scene)
                        }

                        nodes[id] = node
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
            } catch (e: Exception) {
                result.error("PLACE_ERROR", e.message, null)
            }
        }
    }

    // ─── Place Model ─────────────────────────────────────────

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
        val posMap = args["position"] as? Map<*, *>
        val scaleMap = args["scale"] as? Map<*, *>

        if (sourceMap == null) {
            result.error("INVALID_ARGS", "No source provided", null)
            return
        }

        val sourceType = sourceMap["type"] as? Int ?: 0
        val path = sourceMap["path"] as? String ?: ""

        val position = Vector3(
            (posMap?.get("x") as? Double)?.toFloat() ?: 0f,
            (posMap?.get("y") as? Double)?.toFloat() ?: 0f,
            (posMap?.get("z") as? Double)?.toFloat() ?: -1.5f
        )

        val scale = (scaleMap?.get("x") as? Double)?.toFloat() ?: 1f

        activity.runOnUiThread {
            try {
                val modelUri = when (sourceType) {
                    0 -> Uri.parse("file:///android_asset/flutter_assets/$path") // asset
                    2 -> Uri.parse(path) // url
                    else -> Uri.parse(path) // file
                }

                ModelRenderable.builder()
                    .setSource(activity, modelUri)
                    .setIsFilamentGltf(true)
                    .setAsyncLoadEnabled(true)
                    .build()
                    .thenAccept { renderable ->
                        val sceneView = arSceneView ?: return@thenAccept
                        val frame = sceneView.arFrame

                        // Try hit test
                        val hitResults = frame?.hitTest(
                            sceneView.width / 2f,
                            sceneView.height / 2f
                        )

                        val hitResult = hitResults?.firstOrNull {
                            val trackable = it.trackable
                            trackable is Plane &&
                                    trackable.isPoseInPolygon(it.hitPose)
                        }

                        if (hitResult != null) {
                            val anchor = hitResult.createAnchor()
                            val anchorNode = AnchorNode(anchor).apply {
                                setParent(sceneView.scene)
                            }

                            Node().apply {
                                this.renderable = renderable
                                localScale = Vector3(scale, scale, scale)
                                setParent(anchorNode)
                            }

                            nodes[id] = anchorNode
                        } else {
                            Node().apply {
                                this.renderable = renderable
                                localPosition = position
                                localScale = Vector3(scale, scale, scale)
                                setParent(sceneView.scene)
                                nodes[id] = this
                            }
                        }

                        result.success(null)
                    }
                    .exceptionally { throwable ->
                        result.error(
                            "MODEL_ERROR",
                            "Failed to load model: ${throwable.message}",
                            null
                        )
                        null
                    }
            } catch (e: Exception) {
                result.error("MODEL_ERROR", e.message, null)
            }
        }
    }

    // ─── Node Management ─────────────────────────────────────

    private fun removeNode(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<String>("id")
        if (id != null && nodes.containsKey(id)) {
            val node = nodes[id]
            node?.setParent(null)
            nodes.remove(id)
            result.success(null)
        } else {
            result.error("NOT_FOUND", "Node not found: $id", null)
        }
    }

    private fun removeAllNodes(result: MethodChannel.Result) {
        nodes.values.forEach { it.setParent(null) }
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
            node.localPosition = Vector3(
                (posMap["x"] as? Double)?.toFloat() ?: 0f,
                (posMap["y"] as? Double)?.toFloat() ?: 0f,
                (posMap["z"] as? Double)?.toFloat() ?: 0f
            )
        }

        if (scaleMap != null) {
            val sx = (scaleMap["x"] as? Double)?.toFloat() ?: 1f
            val sy = (scaleMap["y"] as? Double)?.toFloat() ?: 1f
            val sz = (scaleMap["z"] as? Double)?.toFloat() ?: 1f
            node.localScale = Vector3(sx, sy, sz)
        }

        if (rotMap != null) {
            val pitch = (rotMap["pitch"] as? Double)?.toFloat() ?: 0f
            val yaw = (rotMap["yaw"] as? Double)?.toFloat() ?: 0f
            val roll = (rotMap["roll"] as? Double)?.toFloat() ?: 0f
            node.localRotation = Quaternion.eulerAngles(Vector3(pitch, yaw, roll))
        }

        result.success(null)
    }

    // ─── Session Control ─────────────────────────────────────

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
            nodes.values.forEach { it.setParent(null) }
            nodes.clear()
            arSceneView?.pause()
            arSceneView?.session?.close()
            arSceneView?.destroy()
            arSceneView = null
            frameLayout.removeAllViews()
            isInitialized = false
            result.success(null)
        } catch (e: Exception) {
            result.error("DISPOSE_ERROR", e.message, null)
        }
    }

    // ─── Helpers ─────────────────────────────────────────────

    private fun sendEvent(type: String, data: Map<String, Any?>) {
        activity.runOnUiThread {
            eventSink?.success(
                mutableMapOf<String, Any?>("type" to type).apply {
                    putAll(data)
                }
            )
        }
    }

    override fun dispose() {
        nodes.values.forEach { it.setParent(null) }
        nodes.clear()
        arSceneView?.pause()
        arSceneView?.session?.close()
        arSceneView?.destroy()
        arSceneView = null
        frameLayout.removeAllViews()
        methodChannel.setMethodCallHandler(null)
    }
}