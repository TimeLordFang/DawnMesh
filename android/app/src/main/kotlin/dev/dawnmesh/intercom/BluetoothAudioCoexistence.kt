package dev.dawnmesh.intercom

import android.media.AudioDeviceInfo

/**
 * 同一进程内向 BLE L2CAP 发送器发布蓝牙耳机共存状态。
 *
 * Android 的 BluetoothSocket 没有公开 L2CAP CoC 连接间隔/优先级 API，能由
 * 应用控制的是写入节奏与语音码率。状态只影响当前进程，不做持久化。
 */
internal object BluetoothAudioCoexistence {
    @Volatile private var active = false

    fun setActive(value: Boolean) {
        active = value
    }

    fun isActive(): Boolean = active

    fun l2capCoalesceMillis(): Long = if (active) 60 else 25
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
