package dev.dawnmesh.intercom

import android.Manifest
import android.content.pm.PackageManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
import android.media.AudioManager
import android.media.AudioAttributes
import android.media.AudioFocusRequest
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.os.PowerManager

/** Foreground microphone lifetime owns CPU/network locks, released on stop. */
class IntercomForegroundService : Service() {
    companion object {
        private const val TAG = "DawnFgs"
        private const val CHANNEL_ID = "dawnmesh_call_v2"
        private const val NOTIFICATION_ID = 4802
        @Volatile var hasAudioFocus = false; private set
        var focusObserver: ((Boolean) -> Unit)? = null
        private val startup = ForegroundStartup()
        private val mainHandler = Handler(Looper.getMainLooper())

        fun start(context: Context, completion: (String?) -> Unit) {
            if (context.checkSelfPermission(Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                completion(context.getString(R.string.call_microphone_permission)); return
            }
            val ticket = startup.request(completion) ?: return
            try {
                context.startForegroundService(Intent(context, IntercomForegroundService::class.java)
                    .putExtra("startupTicket", ticket))
                mainHandler.postDelayed({
                    if (startup.isPending(ticket)) {
                        context.stopService(Intent(context, IntercomForegroundService::class.java))
                        startup.complete(ticket, context.getString(R.string.call_service_failed))
                    }
                }, 8000)
            } catch (error: Exception) {
                Log.e(TAG, "无法启动通话前台服务", error)
                startup.complete(ticket, context.getString(R.string.call_service_failed))
            }
        }

        fun stop(context: Context) {
            startup.stop(context.getString(R.string.call_service_cancelled))
            context.stopService(Intent(context, IntercomForegroundService::class.java))
        }

        fun refreshNotification(context: Context) {
            if (!startup.running) return
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, notification(context))
        }

        private fun notification(context: Context): Notification {
            val controlIntent = PendingIntent.getActivity(context, 4803,
                Intent(context, LockScreenTalkActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val state = when {
                CallControlBridge.muted -> context.getString(R.string.call_muted)
                CallControlBridge.automatic -> context.getString(R.string.call_automatic)
                else -> context.getString(R.string.call_ptt)
            }
            return Notification.Builder(context, CHANNEL_ID)
                .setContentTitle(context.getString(R.string.call_title, context.getString(R.string.app_name)))
                .setContentText(state)
                .setSmallIcon(R.drawable.ic_launcher_monochrome)
                .setContentIntent(controlIntent)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_CALL)
                .addAction(Notification.Action.Builder(
                    android.R.drawable.ic_btn_speak_now, context.getString(R.string.call_panel), controlIntent).build())
                .build()
        }
    }

    private var activeTicket = -1
    private val audioManager by lazy { getSystemService(Context.AUDIO_SERVICE) as AudioManager }
    private val focusRequest by lazy {
        AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN_TRANSIENT)
            .setAudioAttributes(AudioAttributes.Builder()
                .setUsage(AudioAttributes.USAGE_VOICE_COMMUNICATION)
                .setContentType(AudioAttributes.CONTENT_TYPE_SPEECH).build())
            .setAcceptsDelayedFocusGain(false)
            .setOnAudioFocusChangeListener({ change ->
                hasAudioFocus = change == AudioManager.AUDIOFOCUS_GAIN
                focusObserver?.invoke(hasAudioFocus)
                CallControlBridge.command("audioFocus", hasAudioFocus)
            }, Handler(Looper.getMainLooper()))
            .build()
    }
    private var cpuLock: PowerManager.WakeLock? = null
    private var wifiLock: WifiManager.WifiLock? = null
    private val handler = Handler(Looper.getMainLooper())
    private val renewCpuLock = object : Runnable {
        override fun run() {
            // Bounded lease renewed only while this foreground service exists.
            cpuLock?.acquire(30 * 60 * 1000L)
            handler.postDelayed(this, 20 * 60 * 1000L)
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID,
            getString(R.string.call_channel), NotificationManager.IMPORTANCE_LOW).apply {
            description = getString(R.string.call_channel_description)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val ticket = intent?.getIntExtra("startupTicket", -1) ?: -1
        if (!startup.isPending(ticket)) {
            if (!startup.running) stopSelf()
            return START_NOT_STICKY
        }
        activeTicket = ticket
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(
                    NOTIFICATION_ID,
                    notification(this),
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE or
                        ServiceInfo.FOREGROUND_SERVICE_TYPE_MEDIA_PLAYBACK,
                )
            } else startForeground(NOTIFICATION_ID, notification(this))
            if (cpuLock == null) {
                cpuLock = (getSystemService(Context.POWER_SERVICE) as PowerManager)
                    .newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, "DawnMesh:ActiveCall")
                    .apply { setReferenceCounted(false) }
                renewCpuLock.run()
            }
            if (wifiLock == null && !CallControlBridge.bluetooth) {
                val wifi = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
                @Suppress("DEPRECATION")
                val lock = wifi.createWifiLock(WifiManager.WIFI_MODE_FULL_HIGH_PERF, "DawnMesh:ActiveCall")
                wifiLock = lock.apply { setReferenceCounted(false); acquire() }
            }
            hasAudioFocus = audioManager.requestAudioFocus(focusRequest) == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
            if (!hasAudioFocus) throw IllegalStateException("Audio focus unavailable")
            startup.complete(ticket, null)
        } catch (e: Exception) {
            Log.e(TAG, "前台通话服务初始化失败", e)
            stopSelf()
            startup.complete(ticket, getString(R.string.call_service_failed))
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        val stoppedCurrent = startup.stopIfCurrent(activeTicket, getString(R.string.call_service_cancelled))
        audioManager.abandonAudioFocusRequest(focusRequest)
        hasAudioFocus = false
        focusObserver?.invoke(false)
        // Normal leave deactivates controls first. An unexpected service
        // teardown must also close public-room capture owned by Dart/WebRTC.
        if (stoppedCurrent) CallControlBridge.command("serviceFailed", true)
        handler.removeCallbacks(renewCpuLock)
        cpuLock?.let { if (it.isHeld) it.release() }
        wifiLock?.let { if (it.isHeld) it.release() }
        cpuLock = null
        wifiLock = null
        super.onDestroy()
    }
}
