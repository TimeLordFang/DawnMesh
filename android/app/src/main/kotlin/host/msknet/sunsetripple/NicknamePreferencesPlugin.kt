package host.msknet.sunsetripple

import android.content.Context
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/** Only the display name is persisted, never room PINs, keys or conversations. */
internal class NicknamePreferencesPlugin(context: Context, messenger: BinaryMessenger) {
    private val preferences = context.getSharedPreferences("dawnmesh_profile", Context.MODE_PRIVATE)
    private val worker = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private val channel = MethodChannel(messenger, "dev.dawnmesh.intercom/preferences")
    init {
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "getNickname" -> worker.execute {
                    val name = preferences.getString("nickname", null)
                    main.post { result.success(name) }
                }
                "setNickname" -> {
                    val name = call.argument<String>("nickname")
                    if (name == null || name.toByteArray(Charsets.UTF_8).size > 256) {
                        result.error("BAD_NICKNAME", "昵称过长", null)
                    } else worker.execute {
                        val saved = preferences.edit().putString("nickname", name).commit()
                        main.post {
                            if (saved) result.success(null)
                            else result.error("SAVE_FAILED", "昵称未写入存储", null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
    fun dispose() {
        channel.setMethodCallHandler(null)
        worker.shutdown() // Finish queued writes, including the last edit.
    }
}
