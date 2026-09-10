package dev.dawnmesh.intercom

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
 * 同一进程内向 BLE L2CAP 发送器发布蓝牙耳机共存状态。
 *
 * Android 的 BluetoothSocket 没有公开 L2CAP CoC 连接间隔/优先级 API，能由
 * 应用控制的是写入节奏与语音码率。共存状态只影响当前进程；调优档位由
 * 应用私有偏好持久化后同步到这里。
 */
internal object BluetoothAudioCoexistence {
    @Volatile private var active = false
    @Volatile private var tuningProfile = AudioTuningProfile.BALANCED

    fun setActive(value: Boolean) {
        active = value
    }

    fun isActive(): Boolean = active

    fun setTuningProfile(value: AudioTuningProfile) {
        tuningProfile = value
    }

    fun l2capCoalesceMillis(): Long = when {
        tuningProfile == AudioTuningProfile.LOW_LATENCY -> 0
        active -> tuningProfile.l2capCoalesceMillis
        else -> 25
    }

    /** 低延迟档允许发送队列淘汰过时语音；可靠的控制帧从不参与淘汰。 */
    fun dropStaleRealtime(): Boolean = tuningProfile == AudioTuningProfile.LOW_LATENCY

    fun maxRealtimeAgeMillis(): Long = 60
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
