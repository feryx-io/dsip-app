package com.feryx.dsip

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors

/**
 * Native code's way to the app in the Rust core, with or without Dart (app plan A5d-2, as Anvil's A2): a push starts it
 * in a process where Flutter may never run. The app's calls come here as events for Telecom ([CallSystem.fromCore]);
 * what the user does at Telecom goes back ([act]). The Rust side is `app/rust/src/system.rs`.
 */
object CoreLink {
    private const val TAG = "DsipCore"
    private val main = Handler(Looper.getMainLooper())

    /** The Rust calls block: one at a time, never on the main thread. */
    private val worker = Executors.newSingleThreadExecutor()

    private var following = false

    /** The app's folder, where Dart keeps `settings.json` (path_provider's application support directory). */
    private fun dir(context: Context): File = context.filesDir

    /** Whether the app has been set up: there are settings to start from. */
    fun configured(context: Context): Boolean = File(dir(context), "settings.json").exists()

    /** The publisher's push gateway this build was given; empty without one. */
    fun gateway(context: Context): String = context.getString(R.string.dsip_push_gateway)

    /** Load the core and follow the app's calls, once per process. */
    @Synchronized
    fun start(context: Context) {
        val app = context.applicationContext
        DsipNative.init(app, dir(app).path, gateway(app))
        CallService.appContext = app
        if (following) return
        following = true
        Thread({
            while (true) {
                val json = DsipNative.nextCallEvent(60_000) ?: continue
                val event = try {
                    JSONObject(json)
                } catch (e: Exception) {
                    Log.w(TAG, "an unreadable call event: $json", e)
                    continue
                }
                main.post { CallSystem.fromCore(app, event) }
            }
        }, "dsip-calls").apply { isDaemon = true }.start()
    }

    /** Woken by a push: start the app from its settings, unless it runs. [failed] hears why not, on the main thread. */
    fun wake(context: Context, failed: (String) -> Unit) {
        start(context)
        worker.execute {
            val error = DsipNative.wake() ?: return@execute
            Log.w(TAG, "the app did not wake: $error")
            main.post { failed(error) }
        }
    }

    /** Where this install is woken from now on; an empty token is nowhere. */
    fun setPush(context: Context, provider: String, app: String, token: String) {
        start(context)
        worker.execute {
            DsipNative.setPush(provider, app, token)?.let { Log.w(TAG, "the push token was not taken: $it") }
        }
    }

    /** What the user did at the system's call screen, for the app. */
    fun act(action: String, id: Long, extra: Map<String, Any?> = emptyMap()) {
        val json = JSONObject(extra).put("action", action).put("id", id).toString()
        worker.execute {
            DsipNative.act(json)?.let { Log.i(TAG, "$action on call $id: $it") }
        }
    }
}
