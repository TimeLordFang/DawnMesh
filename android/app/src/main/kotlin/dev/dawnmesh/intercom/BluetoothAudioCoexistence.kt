package dev.dawnmesh.intercom

import android.media.AudioDeviceInfo

internal enum class AudioTuningProfile(
    val wireName: String,
    val bluetoothPrebufferFrames: Int,
    val bluetoothMaxBufferFrames: Int,
    val bluetoothMaxAdaptiveFrames: Int,
    val stableFramesBeforeDecay: Int,
    val maxConcealmentFrames: Int,
    val audioTrackBufferFrames: Int,
    val l2capCoalesceMillis: Long,
    val headsetBitrate: Int,
) {
    LOW_LATENCY("low", 4, 18, 10, 50, 2, 2, 35, 8_000),
    BALANCED("balanced", 6, 24, 14, 100, 2, 4, 50, 8_000),
    STABLE("stable", 10, 32, 24, 250, 3, 6, 60, 10_000),
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

    fun l2capCoalesceMillis(): Long =
        if (active) tuningProfile.l2capCoalesceMillis else 25
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
