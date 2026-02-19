package com.example.flutter_ar_easy

import android.app.Activity
import android.content.Context
import androidx.annotation.NonNull
import com.google.ar.core.ArCoreApk
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

class FlutterArEasyPlugin : FlutterPlugin, MethodCallHandler, ActivityAware {

    private lateinit var supportChannel: MethodChannel
    private var activity: Activity? = null
    private var context: Context? = null
    private var pluginBinding: FlutterPlugin.FlutterPluginBinding? = null

    override fun onAttachedToEngine(
        @NonNull flutterPluginBinding: FlutterPlugin.FlutterPluginBinding
    ) {
        pluginBinding = flutterPluginBinding
        context = flutterPluginBinding.applicationContext

        // Support check channel
        supportChannel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            "flutter_ar_easy/support"
        )
        supportChannel.setMethodCallHandler(this)
    }

    override fun onMethodCall(@NonNull call: MethodCall, @NonNull result: Result) {
        when (call.method) {
            "isArSupported" -> checkArSupport(result)
            else -> result.notImplemented()
        }
    }

    private fun checkArSupport(result: Result) {
        val ctx = context
        if (ctx == null) {
            result.success(false)
            return
        }

        try {
            val availability = ArCoreApk.getInstance().checkAvailability(ctx)
            when (availability) {
                ArCoreApk.Availability.SUPPORTED_INSTALLED,
                ArCoreApk.Availability.SUPPORTED_APK_TOO_OLD,
                ArCoreApk.Availability.SUPPORTED_NOT_INSTALLED -> {
                    result.success(true)
                }
                else -> result.success(false)
            }
        } catch (e: Exception) {
            result.success(false)
        }
    }

    // ─── Activity Aware ──────────────────────────────────────

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerViewFactory()
    }

    override fun onDetachedFromActivityForConfigChanges() {
        activity = null
    }

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        activity = binding.activity
        registerViewFactory()
    }

    override fun onDetachedFromActivity() {
        activity = null
    }

    private fun registerViewFactory() {
        val binding = pluginBinding ?: return
        val act = activity ?: return

        binding.platformViewRegistry.registerViewFactory(
            "flutter_ar_easy/ar_view",
            ArViewFactory(act, binding.binaryMessenger)
        )
    }

    override fun onDetachedFromEngine(@NonNull binding: FlutterPlugin.FlutterPluginBinding) {
        supportChannel.setMethodCallHandler(null)
        pluginBinding = null
    }
}
