package dev.rishav.deferred_links

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.res.Resources
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.android.installreferrer.api.InstallReferrerClient
import com.android.installreferrer.api.InstallReferrerStateListener
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.embedding.engine.plugins.activity.ActivityAware
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import java.util.Locale
import java.util.TimeZone

/** Receives App Links (cold + warm) and reads the Play Install Referrer. */
class DeferredLinksPlugin :
    FlutterPlugin,
    MethodCallHandler,
    ActivityAware,
    EventChannel.StreamHandler,
    PluginRegistry.NewIntentListener {

    private lateinit var context: Context
    private lateinit var methods: MethodChannel
    private lateinit var events: EventChannel
    private var sink: EventChannel.EventSink? = null
    private var binding: ActivityPluginBinding? = null
    private val main = Handler(Looper.getMainLooper())

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        methods = MethodChannel(flutterPluginBinding.binaryMessenger, "dev.rishav/deferred_links")
        methods.setMethodCallHandler(this)
        events = EventChannel(flutterPluginBinding.binaryMessenger, "dev.rishav/deferred_links/events")
        events.setStreamHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methods.setMethodCallHandler(null)
        events.setStreamHandler(null)
    }

    // --- ActivityAware: the launch intent and later intents -------------------------------------

    override fun onAttachedToActivity(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addOnNewIntentListener(this)
        if (!launchCaptured) {
            launchCaptured = true
            initialLink = linkFrom(binding.activity.intent, launching = true)
        }
    }

    override fun onDetachedFromActivityForConfigChanges() = detach()
    override fun onReattachedToActivityForConfigChanges(binding: ActivityPluginBinding) {
        this.binding = binding
        binding.addOnNewIntentListener(this)
    }

    override fun onDetachedFromActivity() = detach()

    private fun detach() {
        binding?.removeOnNewIntentListener(this)
        binding = null
    }

    override fun onNewIntent(intent: Intent): Boolean {
        val link = linkFrom(intent, launching = false) ?: return false
        sink?.success(link)
        return false
    }

    private fun linkFrom(intent: Intent?, launching: Boolean): String? {
        if (intent == null || intent.action != Intent.ACTION_VIEW) return null
        // A task restored from recents re-delivers the old intent; ignore it.
        if (launching && intent.flags and Intent.FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY != 0) return null
        return intent.data?.toString()
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    // --- Method channel -----------------------------------------------------------------------

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getInitialLink" -> result.success(initialLink)
            "getInstallReferrer" -> readReferrer(result)
            "isFirstLaunch" -> result.success(!prefs().getBoolean(KEY_CHECKED, false))
            "markDeferredChecked" -> {
                prefs().edit().putBoolean(KEY_CHECKED, true).apply()
                result.success(null)
            }
            "getDeviceSignals" -> {
                val metrics = Resources.getSystem().displayMetrics
                result.success(
                    mapOf(
                        "platform" to "android",
                        "osVersion" to Build.VERSION.RELEASE,
                        "model" to Build.MODEL,
                        "screenWidth" to (metrics.widthPixels / metrics.density).toInt(),
                        "screenHeight" to (metrics.heightPixels / metrics.density).toInt(),
                        "language" to Locale.getDefault().toLanguageTag(),
                        "timezoneOffsetMinutes" to TimeZone.getDefault().getOffset(System.currentTimeMillis()) / 60000,
                    )
                )
            }
            else -> result.notImplemented()
        }
    }

    private fun prefs() = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    /** Never throws to Dart: status is ok | unavailable (final) | transient (retry later). */
    private fun readReferrer(result: Result) {
        var replied = false
        fun reply(map: Map<String, Any?>) {
            main.post {
                if (!replied) {
                    replied = true
                    result.success(map)
                }
            }
        }
        val client = try {
            InstallReferrerClient.newBuilder(context).build()
        } catch (e: Exception) {
            reply(mapOf("status" to "unavailable"))
            return
        }
        try {
            client.startConnection(object : InstallReferrerStateListener {
                override fun onInstallReferrerSetupFinished(code: Int) {
                    when (code) {
                        InstallReferrerClient.InstallReferrerResponse.OK -> {
                            try {
                                val details = client.installReferrer
                                reply(
                                    mapOf(
                                        "status" to "ok",
                                        "referrer" to details.installReferrer,
                                        "clickTimestamp" to details.referrerClickTimestampSeconds,
                                        "installTimestamp" to details.installBeginTimestampSeconds,
                                    )
                                )
                            } catch (e: Exception) {
                                reply(mapOf("status" to "transient"))
                            }
                        }
                        InstallReferrerClient.InstallReferrerResponse.SERVICE_UNAVAILABLE,
                        InstallReferrerClient.InstallReferrerResponse.DEVELOPER_ERROR ->
                            reply(mapOf("status" to "transient"))
                        else -> reply(mapOf("status" to "unavailable"))
                    }
                    try { client.endConnection() } catch (_: Exception) {}
                }

                override fun onInstallReferrerServiceDisconnected() {
                    reply(mapOf("status" to "transient"))
                }
            })
        } catch (e: Exception) {
            reply(mapOf("status" to "transient"))
        }
    }

    companion object {
        private const val PREFS = "dev.rishav.deferred_links"
        private const val KEY_CHECKED = "deferred_checked"
        private var launchCaptured = false
        private var initialLink: String? = null
    }
}
