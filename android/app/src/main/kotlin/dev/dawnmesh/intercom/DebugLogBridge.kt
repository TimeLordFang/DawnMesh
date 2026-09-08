package dev.dawnmesh.intercom

import android.Manifest
import android.annotation.SuppressLint
import android.app.ActivityManager
import android.bluetooth.BluetoothManager
import android.content.Context
import android.content.pm.PackageManager
import android.media.AudioManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.os.Process
import android.os.SystemClock
import android.util.Log as AndroidLog
import android.net.wifi.WifiManager
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/** Routes native diagnostics to the in-app log page only when the user enables it. */
internal object DebugLogBridge : EventChannel.StreamHandler {
    private const val EVENT_CHANNEL = "dev.dawnmesh.intercom/debug_logs"
    private const val CONTROL_CHANNEL = "dev.dawnmesh.intercom/debug_log_control"
    private const val PREFERENCES = "dawnmesh_profile"
    private const val ENABLED_KEY = "debug_logging_enabled"
    private const val SYSTEM_TAG = "DawnSystem"

    private val main = Handler(Looper.getMainLooper())
    @Volatile private var enabled = false
    @Volatile private var sink: EventChannel.EventSink? = null
    private var appContext: Context? = null
    private var eventChannel: EventChannel? = null
    private var controlChannel: MethodChannel? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        appContext = context.applicationContext
        enabled = appContext!!.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE)
            .getBoolean(ENABLED_KEY, false)
        eventChannel?.setStreamHandler(null)
        controlChannel?.setMethodCallHandler(null)
        eventChannel = EventChannel(messenger, EVENT_CHANNEL).also {
            it.setStreamHandler(this)
        }
        controlChannel = MethodChannel(messenger, CONTROL_CHANNEL).also { channel ->
            channel.setMethodCallHandler { call, result ->
                if (call.method != "captureSystemSnapshot") {
                    result.notImplemented()
                } else if (!enabled) {
                    result.success(false)
                } else {
                    captureSystemSnapshot()
                    result.success(true)
                }
            }
        }
    }

    fun detach() {
        eventChannel?.setStreamHandler(null)
        eventChannel = null
        controlChannel?.setMethodCallHandler(null)
        controlChannel = null
        sink = null
        appContext = null
    }

    fun setEnabled(value: Boolean) {
        enabled = value
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        sink = events
        if (enabled) captureSystemSnapshot()
    }

    override fun onCancel(arguments: Any?) {
        sink = null
    }

    fun d(tag: String, message: String) = write("debug", tag, message)
    fun i(tag: String, message: String) = write("info", tag, message)
    fun w(tag: String, message: String, error: Throwable? = null) =
        write("warn", tag, message, error)
    fun e(tag: String, message: String, error: Throwable? = null) =
        write("error", tag, message, error)

    /** Emits only app-readable state. Android does not grant normal apps full system logcat access. */
    @SuppressLint("MissingPermission")
    private fun captureSystemSnapshot() {
        val context = appContext ?: return
        try {
            val runtime = Runtime.getRuntime()
            val activityManager = context.getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val memory = ActivityManager.MemoryInfo().also(activityManager::getMemoryInfo)
            val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            val audio = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
            val wifi = context.applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
            val connectivity = context.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager
            val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
            val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION") packageInfo.versionCode.toLong()
            }

            i(
                SYSTEM_TAG,
                "app=${context.packageName}; version=${packageInfo.versionName}($versionCode); " +
                    "pid=${Process.myPid()}; debuggable=${context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0}",
            )

            i(
                SYSTEM_TAG,
                "device=${Build.MANUFACTURER} ${Build.MODEL}; product=${Build.PRODUCT}; " +
                    "hardware=${Build.HARDWARE}${if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) "; soc=${Build.SOC_MODEL}" else ""}",
            )
            i(
                SYSTEM_TAG,
                "android=${Build.VERSION.RELEASE}; sdk=${Build.VERSION.SDK_INT}; " +
                    "securityPatch=${Build.VERSION.SECURITY_PATCH}; abis=${Build.SUPPORTED_ABIS.joinToString()}",
            )
            i(
                SYSTEM_TAG,
                "runtime processors=${runtime.availableProcessors()}; heapUsed=${runtime.totalMemory() - runtime.freeMemory()}; " +
                    "heapMax=${runtime.maxMemory()}; ramAvailable=${memory.availMem}; ramLow=${memory.lowMemory}; uptimeMs=${SystemClock.elapsedRealtime()}",
            )
            i(
                SYSTEM_TAG,
                "powerSave=${power.isPowerSaveMode}; batteryOptimizationIgnored=${power.isIgnoringBatteryOptimizations(context.packageName)}; interactive=${power.isInteractive}",
            )
            i(
                SYSTEM_TAG,
                "audio sampleRate=${audio.getProperty(AudioManager.PROPERTY_OUTPUT_SAMPLE_RATE)}; " +
                    "framesPerBuffer=${audio.getProperty(AudioManager.PROPERTY_OUTPUT_FRAMES_PER_BUFFER)}; " +
                    "mode=${audio.mode}; micMuted=${audio.isMicrophoneMute}; musicVolume=${audio.getStreamVolume(AudioManager.STREAM_MUSIC)}/${audio.getStreamMaxVolume(AudioManager.STREAM_MUSIC)}",
            )
            val devices = (
                audio.getDevices(AudioManager.GET_DEVICES_INPUTS) +
                    audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
            ).distinctBy { it.id }.joinToString(" | ") { device ->
                "type=${device.type},name=${device.productName},source=${device.isSource},sink=${device.isSink}"
            }
            i(SYSTEM_TAG, "audioDevices=${devices.ifEmpty { "none" }}")

            val wifiDetails = buildString {
                append("wifiEnabled=${wifi.isWifiEnabled}; 5GHz=${wifi.is5GHzBandSupported}")
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                    append("; 6GHz=${wifi.is6GHzBandSupported}")
                }
                append("; wifiDirect=${context.packageManager.hasSystemFeature(PackageManager.FEATURE_WIFI_DIRECT)}")
            }
            i(SYSTEM_TAG, wifiDetails)

            val capabilities = connectivity.activeNetwork?.let(connectivity::getNetworkCapabilities)
            if (capabilities == null) {
                i(SYSTEM_TAG, "activeNetwork=none")
            } else {
                val transports = buildList {
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) add("wifi")
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR)) add("cellular")
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_BLUETOOTH)) add("bluetooth")
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET)) add("ethernet")
                    if (capabilities.hasTransport(NetworkCapabilities.TRANSPORT_VPN)) add("vpn")
                }
                i(
                    SYSTEM_TAG,
                    "activeNetwork transports=${transports.ifEmpty { listOf("other") }.joinToString()}; " +
                        "internet=${capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)}; " +
                        "validated=${capabilities.hasCapability(NetworkCapabilities.NET_CAPABILITY_VALIDATED)}; " +
                        "downKbps=${capabilities.linkDownstreamBandwidthKbps}; upKbps=${capabilities.linkUpstreamBandwidthKbps}",
                )
            }

            if (hasPermission(context, Manifest.permission.BLUETOOTH_CONNECT) ||
                Build.VERSION.SDK_INT < Build.VERSION_CODES.S
            ) {
                val adapter = (context.getSystemService(Context.BLUETOOTH_SERVICE) as BluetoothManager).adapter
                if (adapter == null) {
                    i(SYSTEM_TAG, "bluetooth=unavailable")
                } else {
                    i(
                        SYSTEM_TAG,
                        "bluetooth enabled=${adapter.isEnabled}; state=${adapter.state}; " +
                            "multiAdvertise=${adapter.isMultipleAdvertisementSupported}; " +
                            "offloadedFilter=${adapter.isOffloadedFilteringSupported}; " +
                            "offloadedBatch=${adapter.isOffloadedScanBatchingSupported}; " +
                            "le2M=${adapter.isLe2MPhySupported}; leCoded=${adapter.isLeCodedPhySupported}; " +
                            "extendedAdv=${adapter.isLeExtendedAdvertisingSupported}; maxAdvBytes=${adapter.leMaximumAdvertisingDataLength}",
                    )
                }
            } else {
                i(SYSTEM_TAG, "bluetooth=permission unavailable")
            }

            val permissions = buildList {
                add(Manifest.permission.RECORD_AUDIO)
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                    add(Manifest.permission.BLUETOOTH_CONNECT)
                    add(Manifest.permission.BLUETOOTH_SCAN)
                    add(Manifest.permission.BLUETOOTH_ADVERTISE)
                }
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                    add(Manifest.permission.NEARBY_WIFI_DEVICES)
                    add(Manifest.permission.POST_NOTIFICATIONS)
                } else {
                    add(Manifest.permission.ACCESS_FINE_LOCATION)
                }
            }
            val missing = permissions.filterNot { hasPermission(context, it) }
            i(SYSTEM_TAG, "permissions missing=${missing.ifEmpty { listOf("none") }.joinToString()}")
        } catch (error: Throwable) {
            w(SYSTEM_TAG, "采集系统快照失败", error)
        }
    }

    private fun hasPermission(context: Context, permission: String): Boolean =
        context.checkSelfPermission(permission) == PackageManager.PERMISSION_GRANTED

    private fun write(level: String, tag: String, message: String, error: Throwable? = null) {
        if (!enabled) return
        when (level) {
            "debug" -> AndroidLog.d(tag, message)
            "info" -> AndroidLog.i(tag, message)
            "warn" -> AndroidLog.w(tag, message, error)
            else -> AndroidLog.e(tag, message, error)
        }
        val payload = mapOf(
            "level" to level,
            "tag" to tag,
            "message" to message,
            "error" to error?.let { "${it.javaClass.simpleName}: ${it.message.orEmpty()}" },
        )
        main.post {
            if (enabled) sink?.success(payload)
        }
    }
}

/** Drop-in facade for existing native diagnostics. */
internal object Log {
    fun d(tag: String, message: String) = DebugLogBridge.d(tag, message)
    fun i(tag: String, message: String) = DebugLogBridge.i(tag, message)
    fun w(tag: String, message: String, error: Throwable? = null) =
        DebugLogBridge.w(tag, message, error)
    fun e(tag: String, message: String, error: Throwable? = null) =
        DebugLogBridge.e(tag, message, error)
}
