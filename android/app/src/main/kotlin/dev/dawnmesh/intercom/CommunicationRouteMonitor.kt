package dev.dawnmesh.intercom

import android.bluetooth.BluetoothHeadset
import android.bluetooth.BluetoothProfile
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log

/** Debounce physical headset changes; never infer a broken mic from silence. */
class CommunicationRouteMonitor(
    private val context: Context,
    private val changed: () -> Unit,
) {
    private val manager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
    private val handler = Handler(Looper.getMainLooper())
    private var active = false
    private var signature = ""
    private var routeGeneration = 0
    private var physicalChange = false
    private val pending = Runnable {
        val next = inputSignature()
        val notify = physicalChange || next != signature
        physicalChange = false
        signature = next
        if (active && notify) changed()
    }
    private fun schedule() {
        handler.removeCallbacks(pending)
        handler.postDelayed(pending, 1200)
    }
    private fun inputSignature() = manager.getDevices(AudioManager.GET_DEVICES_INPUTS)
        .filter { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO ||
            (Build.VERSION.SDK_INT >= 31 && it.type == AudioDeviceInfo.TYPE_BLE_HEADSET) }
        .map { "${it.type}:${it.productName}" }.sorted().joinToString()
    private val callback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(devices: Array<out AudioDeviceInfo>?) = inspect()
        override fun onAudioDevicesRemoved(devices: Array<out AudioDeviceInfo>?) = inspect()
        private fun inspect() {
            val next = inputSignature()
            if (next != signature) schedule()
        }
    }
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context?, intent: Intent?) {
            val state = intent?.getIntExtra(BluetoothProfile.EXTRA_STATE, -1)
            if (state == BluetoothProfile.STATE_CONNECTED || state == BluetoothProfile.STATE_DISCONNECTED) {
                physicalChange = true
                schedule()
            }
        }
    }
    fun start() {
        if (active) return
        active = true
        signature = inputSignature()
        manager.registerAudioDeviceCallback(callback, handler)
        val filter = IntentFilter(BluetoothHeadset.ACTION_CONNECTION_STATE_CHANGED)
        if (Build.VERSION.SDK_INT >= 33) context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
        else @Suppress("DEPRECATION") context.registerReceiver(receiver, filter)
    }
    fun stop() {
        if (!active) return
        active = false
        routeGeneration++
        handler.removeCallbacks(pending)
        manager.unregisterAudioDeviceCallback(callback)
        context.unregisterReceiver(receiver)
    }
    /** WebRTC owns the recording; only restore Android's bidirectional route. */
    fun restoreInternetRoute(ready: () -> Unit) {
        val generation = ++routeGeneration
        try {
            manager.mode = AudioManager.MODE_IN_COMMUNICATION
            if (Build.VERSION.SDK_INT >= 31) {
                val bluetooth = manager.availableCommunicationDevices.firstOrNull {
                    it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == AudioDeviceInfo.TYPE_BLE_HEADSET
                }
                manager.clearCommunicationDevice()
                if (bluetooth != null && manager.setCommunicationDevice(bluetooth)) {
                    var attempts = 0
                    fun awaitRoute() {
                        if (!active || generation != routeGeneration) return
                        if (manager.communicationDevice?.id == bluetooth.id || attempts++ >= 20) ready()
                        else handler.postDelayed({ awaitRoute() }, 250)
                    }
                    handler.postDelayed({ awaitRoute() }, 250)
                    return
                }
            } else {
                @Suppress("DEPRECATION")
                if (manager.getDevices(AudioManager.GET_DEVICES_OUTPUTS).any { it.type == AudioDeviceInfo.TYPE_BLUETOOTH_SCO || it.type == AudioDeviceInfo.TYPE_BLUETOOTH_A2DP }) {
                    manager.stopBluetoothSco()
                    manager.startBluetoothSco()
                    manager.isBluetoothScoOn = true
                }
            }
        } catch (e: RuntimeException) { Log.w("DawnAudio", "恢复蓝牙通信路由失败", e) }
        if (active && generation == routeGeneration) handler.postDelayed({ if (active && generation == routeGeneration) ready() }, 1200)
    }
}
