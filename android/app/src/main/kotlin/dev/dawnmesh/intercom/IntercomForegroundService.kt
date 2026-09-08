package dev.dawnmesh.intercom

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.wifi.WifiManager
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
        @Volatile private var running = false

        fun start(context: Context): Boolean = try {
            context.startForegroundService(Intent(context, IntercomForegroundService::class.java))
            true
        } catch (e: Exception) {
            Log.e(TAG, "无法启动通话前台服务", e)
            false
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, IntercomForegroundService::class.java))
        }

        fun refreshNotification(context: Context) {
            if (!running) return
            (context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .notify(NOTIFICATION_ID, notification(context))
        }

        private fun notification(context: Context): Notification {
            val controlIntent = PendingIntent.getActivity(context, 4803,
                Intent(context, LockScreenTalkActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
            val state = when {
                CallControlBridge.muted -> "已静音 · 仍可收听"
                CallControlBridge.automatic -> "自动通话 · 有声音时发送"
                else -> "按住对讲 · 点此打开锁屏对讲面板"
            }
            return Notification.Builder(context, CHANNEL_ID)
                .setContentTitle(context.getString(R.string.app_name) + " · 房间通话")
                .setContentText(state)
                .setSmallIcon(android.R.drawable.ic_btn_speak_now)
                .setContentIntent(controlIntent)
                .setVisibility(Notification.VISIBILITY_PUBLIC)
                .setOnlyAlertOnce(true)
                .setOngoing(true)
                .setCategory(Notification.CATEGORY_CALL)
                .addAction(Notification.Action.Builder(
                    android.R.drawable.ic_btn_speak_now, "通话面板", controlIntent).build())
                .build()
        }
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
            "房间通话与锁屏控制", NotificationManager.IMPORTANCE_LOW).apply {
            description = "通话期间持续收发，点通知打开按住对讲面板"
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            setShowBadge(false)
        })
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                startForeground(NOTIFICATION_ID, notification(this), ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE)
            } else startForeground(NOTIFICATION_ID, notification(this))
            running = true
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
        } catch (e: Exception) {
            Log.e(TAG, "前台通话服务初始化失败", e)
            stopSelf()
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        running = false
        handler.removeCallbacks(renewCpuLock)
        cpuLock?.let { if (it.isHeld) it.release() }
        wifiLock?.let { if (it.isHeld) it.release() }
        cpuLock = null
        wifiLock = null
        super.onDestroy()
    }
}
