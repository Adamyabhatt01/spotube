package oss.krtirtho.spotube

import android.app.ActivityManager
import android.content.Context
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding

/**
 * Answers the host's memory questions on the platform channel
 * `oss.krtirtho.spotube/device_memory`.
 *
 * The only fact that needs the platform is Android's per-app heap limit
 * (`ActivityManager.getMemoryClass()`): the point at which the system starts
 * killing the app for being too large. It is much smaller than the device's
 * total RAM, and it is the number the image caches should budget against.
 *
 * The channel is optional. If it is not answered, the host falls back to
 * the device total (or a fixed value), so a missing or refused channel
 * degrades the budget rather than breaking the app.
 */
class DeviceMemoryChannel : FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware {
    private var channel: MethodChannel? = null
    private var context: Context? = null

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        context = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, CHANNEL_NAME).also {
            it.setMethodCallHandler(this)
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
        channel = null
        context = null
    }

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivityForConfigChanges() {}

    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {}

    override fun onDetachedFromActivity() {}

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "appHeapLimitBytes" -> {
                val limit = appHeapLimitBytes()
                if (limit == null) {
                    result.success(null)
                } else {
                    result.success(limit)
                }
            }
            else -> result.notImplemented()
        }
    }

    /**
     * The per-app heap limit in bytes, or null when it cannot be read.
     *
     * `largeMemoryClass` is Android's way of saying "this app may use more
     * than the standard limit". This app does not request it, so the
     * standard class is the number to budget against.
     */
    private fun appHeapLimitBytes(): Long? {
        val ctx = context ?: return null
        return try {
            val am = ctx.getSystemService(Context.ACTIVITY_SERVICE) as? ActivityManager
            val megabytes = am?.memoryClass ?: return null
            if (megabytes <= 0) null else megabytes.toLong() * 1024L * 1024L
        } catch (_: Throwable) {
            null
        }
    }

    companion object {
        const val CHANNEL_NAME = "oss.krtirtho.spotube/device_memory"
    }
}
