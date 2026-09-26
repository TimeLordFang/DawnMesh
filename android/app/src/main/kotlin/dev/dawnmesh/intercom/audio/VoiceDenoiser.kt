package dev.dawnmesh.intercom.audio

import androidx.annotation.Keep
import java.nio.ByteBuffer

/** Owned by one capture thread; close only after that callback has stopped. */
@Keep
class VoiceDenoiser(rate: Int) : AutoCloseable {
    companion object {
        init { System.loadLibrary("dawn_mesh_native") }
    }
    private var handle = nativeCreate(rate)
    init { check(handle != 0L) { "Cannot create voice denoiser for $rate Hz" } }
    fun process(samples: ShortArray, level: Int) = nativePcm(handle, samples, level)
    fun process(buffer: ByteBuffer, frames: Int, level: Int) = nativeFloat(handle, buffer, frames, level)
    override fun close() {
        if (handle != 0L) nativeDestroy(handle)
        handle = 0
    }
    private external fun nativeCreate(rate: Int): Long
    private external fun nativeDestroy(handle: Long)
    private external fun nativePcm(handle: Long, samples: ShortArray, level: Int)
    private external fun nativeFloat(handle: Long, buffer: ByteBuffer, frames: Int, level: Int)
}
