package dev.dawnmesh.intercom

import android.content.SharedPreferences
import android.media.AudioDeviceInfo

internal enum class AudioTuningProfile(
    val wireName: String,
    val bluetoothPrebufferFrames: Int,
    val bluetoothMaxBufferFrames: Int,
    val bluetoothMaxAdaptiveFrames: Int,
    val maxPlayoutQueueFrames: Int,
    val stableFramesBeforeDecay: Int,
    val maxConcealmentFrames: Int,
    val audioTrackBufferFrames: Int,
    val l2capCoalesceMillis: Long,
    val headsetBitrate: Int,
) {
    // 低延迟档以“现在听到”为第一目标：40ms 起播、最多保留 60ms 待播语音，
    // AudioTrack 只请求一帧，L2CAP 不等待合并。拥塞时直接跳到最新语音。
    LOW_LATENCY("low", 2, 8, 4, 3, 25, 2, 1, 0, 8_000),
    BALANCED("balanced", 6, 24, 14, 24, 100, 2, 4, 50, 8_000),
    STABLE("stable", 10, 32, 24, 32, 250, 3, 6, 60, 10_000),
    ;

    companion object {
        fun fromWireName(value: String?): AudioTuningProfile =
            entries.firstOrNull { it.wireName == value } ?: BALANCED
    }
}

/**
 * 可在调试页热更新的音频传输参数。所有数值都以 20ms Opus 帧为基本单位；
 * 使用不可变快照，音频线程和蓝牙写线程读取时不需要加锁。
 */
internal data class AudioTuningParameters(
    val profile: AudioTuningProfile,
    val bluetoothPrebufferFrames: Int,
    val bluetoothMaxBufferFrames: Int,
    val bluetoothMaxAdaptiveFrames: Int,
    val maxPlayoutQueueFrames: Int,
    val stableFramesBeforeDecay: Int,
    val maxConcealmentFrames: Int,
    val audioTrackBufferFrames: Int,
    val l2capCoalesceMillis: Long,
    val headsetBitrate: Int,
    val dropStaleRealtime: Boolean,
    val maxRealtimeAgeMillis: Long,
    val flushEveryWrite: Boolean,
) {
    fun toMap(): Map<String, Any> = mapOf(
        "profile" to profile.wireName,
        "prebufferFrames" to bluetoothPrebufferFrames,
        "maxBufferFrames" to bluetoothMaxBufferFrames,
        "maxAdaptiveFrames" to bluetoothMaxAdaptiveFrames,
        "maxPlayoutQueueFrames" to maxPlayoutQueueFrames,
        "stableFramesBeforeDecay" to stableFramesBeforeDecay,
        "maxConcealmentFrames" to maxConcealmentFrames,
        "audioTrackBufferFrames" to audioTrackBufferFrames,
        "l2capCoalesceMillis" to l2capCoalesceMillis,
        "headsetBitrate" to headsetBitrate,
        "dropStaleRealtime" to dropStaleRealtime,
        "maxRealtimeAgeMillis" to maxRealtimeAgeMillis,
        "flushEveryWrite" to flushEveryWrite,
    )

    fun persist(editor: SharedPreferences.Editor): SharedPreferences.Editor = editor
        .putBoolean(PREF_CUSTOM, true)
        .putString(PREF_PROFILE, profile.wireName)
        .putInt(PREF_PREBUFFER, bluetoothPrebufferFrames)
        .putInt(PREF_MAX_BUFFER, bluetoothMaxBufferFrames)
        .putInt(PREF_MAX_ADAPTIVE, bluetoothMaxAdaptiveFrames)
        .putInt(PREF_MAX_PLAYOUT, maxPlayoutQueueFrames)
        .putInt(PREF_STABLE_DECAY, stableFramesBeforeDecay)
        .putInt(PREF_CONCEALMENT, maxConcealmentFrames)
        .putInt(PREF_TRACK_BUFFER, audioTrackBufferFrames)
        .putLong(PREF_COALESCE, l2capCoalesceMillis)
        .putInt(PREF_BITRATE, headsetBitrate)
        .putBoolean(PREF_DROP_STALE, dropStaleRealtime)
        .putLong(PREF_MAX_AGE, maxRealtimeAgeMillis)
        .putBoolean(PREF_FLUSH, flushEveryWrite)

    companion object {
        private const val PREF_CUSTOM = "audio_tuning_custom"
        private const val PREF_PROFILE = "audio_tuning_profile"
        private const val PREF_PREBUFFER = "audio_prebuffer_frames"
        private const val PREF_MAX_BUFFER = "audio_max_buffer_frames"
        private const val PREF_MAX_ADAPTIVE = "audio_max_adaptive_frames"
        private const val PREF_MAX_PLAYOUT = "audio_max_playout_frames"
        private const val PREF_STABLE_DECAY = "audio_stable_decay_frames"
        private const val PREF_CONCEALMENT = "audio_concealment_frames"
        private const val PREF_TRACK_BUFFER = "audio_track_buffer_frames"
        private const val PREF_COALESCE = "audio_l2cap_coalesce_ms"
        private const val PREF_BITRATE = "audio_headset_bitrate"
        private const val PREF_DROP_STALE = "audio_drop_stale"
        private const val PREF_MAX_AGE = "audio_max_realtime_age_ms"
        private const val PREF_FLUSH = "audio_flush_every_write"

        fun defaults(profile: AudioTuningProfile): AudioTuningParameters =
            AudioTuningParameters(
                profile = profile,
                bluetoothPrebufferFrames = profile.bluetoothPrebufferFrames,
                bluetoothMaxBufferFrames = profile.bluetoothMaxBufferFrames,
                bluetoothMaxAdaptiveFrames = profile.bluetoothMaxAdaptiveFrames,
                maxPlayoutQueueFrames = profile.maxPlayoutQueueFrames,
                stableFramesBeforeDecay = profile.stableFramesBeforeDecay,
                maxConcealmentFrames = profile.maxConcealmentFrames,
                audioTrackBufferFrames = profile.audioTrackBufferFrames,
                l2capCoalesceMillis = profile.l2capCoalesceMillis,
                headsetBitrate = profile.headsetBitrate,
                dropStaleRealtime = profile == AudioTuningProfile.LOW_LATENCY,
                maxRealtimeAgeMillis = 60,
                // 测量版默认保持 dev.19 行为，调试页可即时关闭以做 A/B 对照。
                flushEveryWrite = true,
            )

        fun fromMap(raw: Map<*, *>, fallback: AudioTuningParameters): AudioTuningParameters {
            fun int(name: String, default: Int): Int = (raw[name] as? Number)?.toInt() ?: default
            fun long(name: String, default: Long): Long = (raw[name] as? Number)?.toLong() ?: default
            fun bool(name: String, default: Boolean): Boolean = raw[name] as? Boolean ?: default
            val profile = (raw["profile"] as? String)?.let(AudioTuningProfile::fromWireName)
                ?: fallback.profile
            val prebuffer = int("prebufferFrames", fallback.bluetoothPrebufferFrames).coerceIn(1, 15)
            val adaptive = int("maxAdaptiveFrames", fallback.bluetoothMaxAdaptiveFrames)
                .coerceIn(prebuffer, 30)
            val playout = int("maxPlayoutQueueFrames", fallback.maxPlayoutQueueFrames)
                .coerceIn(1, 32)
            val maxBuffer = int("maxBufferFrames", fallback.bluetoothMaxBufferFrames)
                .coerceIn(maxOf(prebuffer, adaptive, playout), 32)
            return AudioTuningParameters(
                profile = profile,
                bluetoothPrebufferFrames = prebuffer,
                bluetoothMaxBufferFrames = maxBuffer,
                bluetoothMaxAdaptiveFrames = adaptive.coerceAtMost(maxBuffer),
                maxPlayoutQueueFrames = playout.coerceAtMost(maxBuffer),
                stableFramesBeforeDecay = int("stableFramesBeforeDecay", fallback.stableFramesBeforeDecay)
                    .coerceIn(10, 500),
                maxConcealmentFrames = int("maxConcealmentFrames", fallback.maxConcealmentFrames)
                    .coerceIn(0, 5),
                audioTrackBufferFrames = int("audioTrackBufferFrames", fallback.audioTrackBufferFrames)
                    .coerceIn(1, 12),
                l2capCoalesceMillis = long("l2capCoalesceMillis", fallback.l2capCoalesceMillis)
                    .coerceIn(0, 100),
                headsetBitrate = int("headsetBitrate", fallback.headsetBitrate).coerceIn(6_000, 16_000),
                dropStaleRealtime = bool("dropStaleRealtime", fallback.dropStaleRealtime),
                maxRealtimeAgeMillis = long("maxRealtimeAgeMillis", fallback.maxRealtimeAgeMillis)
                    .coerceIn(20, 300),
                flushEveryWrite = bool("flushEveryWrite", fallback.flushEveryWrite),
            )
        }

        fun load(preferences: SharedPreferences): AudioTuningParameters {
            val profile = AudioTuningProfile.fromWireName(
                preferences.getString(PREF_PROFILE, "balanced"),
            )
            val fallback = defaults(profile)
            if (!preferences.getBoolean(PREF_CUSTOM, false)) return fallback
            return fromMap(
                mapOf(
                    "profile" to profile.wireName,
                    "prebufferFrames" to preferences.getInt(PREF_PREBUFFER, fallback.bluetoothPrebufferFrames),
                    "maxBufferFrames" to preferences.getInt(PREF_MAX_BUFFER, fallback.bluetoothMaxBufferFrames),
                    "maxAdaptiveFrames" to preferences.getInt(PREF_MAX_ADAPTIVE, fallback.bluetoothMaxAdaptiveFrames),
                    "maxPlayoutQueueFrames" to preferences.getInt(PREF_MAX_PLAYOUT, fallback.maxPlayoutQueueFrames),
                    "stableFramesBeforeDecay" to preferences.getInt(PREF_STABLE_DECAY, fallback.stableFramesBeforeDecay),
                    "maxConcealmentFrames" to preferences.getInt(PREF_CONCEALMENT, fallback.maxConcealmentFrames),
                    "audioTrackBufferFrames" to preferences.getInt(PREF_TRACK_BUFFER, fallback.audioTrackBufferFrames),
                    "l2capCoalesceMillis" to preferences.getLong(PREF_COALESCE, fallback.l2capCoalesceMillis),
                    "headsetBitrate" to preferences.getInt(PREF_BITRATE, fallback.headsetBitrate),
                    "dropStaleRealtime" to preferences.getBoolean(PREF_DROP_STALE, fallback.dropStaleRealtime),
                    "maxRealtimeAgeMillis" to preferences.getLong(PREF_MAX_AGE, fallback.maxRealtimeAgeMillis),
                    "flushEveryWrite" to preferences.getBoolean(PREF_FLUSH, fallback.flushEveryWrite),
                ),
                fallback,
            )
        }

        fun resetToProfile(editor: SharedPreferences.Editor, profile: AudioTuningProfile) = editor
            .putString(PREF_PROFILE, profile.wireName)
            .putBoolean(PREF_CUSTOM, false)
    }
}

/**
 * 同一进程内向 BLE L2CAP 发送器发布蓝牙耳机共存状态。
 *
 * Android 的 BluetoothSocket 没有公开 L2CAP CoC 连接间隔/优先级 API，能由
 * 应用控制的是写入节奏与语音码率。共存状态只影响当前进程；调优档位由
 * 应用私有偏好持久化后同步到这里。
 */
internal object BluetoothAudioCoexistence {
    @Volatile private var active = false
    @Volatile private var parameters = AudioTuningParameters.defaults(AudioTuningProfile.BALANCED)

    fun setActive(value: Boolean) {
        active = value
    }

    fun isActive(): Boolean = active

    fun setTuningProfile(value: AudioTuningProfile) {
        parameters = AudioTuningParameters.defaults(value)
    }

    fun setParameters(value: AudioTuningParameters) { parameters = value }

    fun l2capCoalesceMillis(): Long = when {
        active -> parameters.l2capCoalesceMillis
        else -> 25
    }

    /** 低延迟档允许发送队列淘汰过时语音；可靠的控制帧从不参与淘汰。 */
    fun dropStaleRealtime(): Boolean = parameters.dropStaleRealtime

    fun maxRealtimeAgeMillis(): Long = parameters.maxRealtimeAgeMillis

    fun flushEveryWrite(): Boolean = parameters.flushEveryWrite

    fun diagnostics(): String = parameters.run {
        "profile=${profile.wireName},bitrate=${headsetBitrate}bps,coalesce=${l2capCoalesceMillis}ms," +
            "dropStale=$dropStaleRealtime,maxAge=${maxRealtimeAgeMillis}ms,flush=$flushEveryWrite"
    }
}

internal fun audioDeviceTypeName(type: Int): String = when (type) {
    AudioDeviceInfo.TYPE_BUILTIN_EARPIECE -> "EARPIECE"
    AudioDeviceInfo.TYPE_BUILTIN_SPEAKER -> "SPEAKER"
    AudioDeviceInfo.TYPE_WIRED_HEADSET -> "WIRED_HEADSET"
    AudioDeviceInfo.TYPE_WIRED_HEADPHONES -> "WIRED_HEADPHONES"
    AudioDeviceInfo.TYPE_BLUETOOTH_SCO -> "BT_SCO"
    AudioDeviceInfo.TYPE_BLUETOOTH_A2DP -> "BT_A2DP"
    AudioDeviceInfo.TYPE_BUILTIN_MIC -> "BUILTIN_MIC"
    AudioDeviceInfo.TYPE_USB_DEVICE -> "USB_DEVICE"
    AudioDeviceInfo.TYPE_USB_HEADSET -> "USB_HEADSET"
    AudioDeviceInfo.TYPE_HEARING_AID -> "HEARING_AID"
    AudioDeviceInfo.TYPE_BLE_HEADSET -> "BLE_HEADSET"
    AudioDeviceInfo.TYPE_BLE_SPEAKER -> "BLE_SPEAKER"
    else -> "OTHER"
}
