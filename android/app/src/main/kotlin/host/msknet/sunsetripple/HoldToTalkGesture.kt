package host.msknet.sunsetripple

/** A cancelled hold cannot resume until a fresh pointer-down. */
internal class HoldToTalkGesture(private val changed: (Boolean) -> Unit) {
    private var pointer = -1
    private var held = false

    fun down(id: Int, allowed: Boolean) {
        if (pointer != -1) return
        pointer = id
        if (allowed) setHeld(true)
    }

    fun move(id: Int, inside: Boolean) {
        if (pointer == id && !inside) setHeld(false)
    }

    fun up(id: Int) {
        if (pointer != id) return
        pointer = -1
        setHeld(false)
    }

    fun cancel() {
        pointer = -1
        setHeld(false)
    }

    private fun setHeld(value: Boolean) {
        if (held == value) return
        held = value
        changed(value)
    }
}
