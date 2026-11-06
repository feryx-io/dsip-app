package com.thevoiceguy.dsip

import android.content.Context

/** The Rust core, loaded by the app so it knows the JVM and the context (app/rust/src/android.rs). */
object DsipNative {
    init {
        System.loadLibrary("dsip_app_bridge")
    }

    /** Hands the JVM, the application context, the app's folder and the build's push gateway to the Rust core. */
    @JvmStatic
    external fun init(context: Context, dir: String, gateway: String)

    /** A push came: start the app from its settings, unless it runs. Null, or what went wrong. */
    @JvmStatic
    external fun wake(): String?

    /** Where this install is woken (an empty token: nowhere). Null, or what went wrong. */
    @JvmStatic
    external fun setPush(provider: String, app: String, token: String): String?

    /** The next event for the system's call screen as JSON, or null when none came within [timeoutMs]. */
    @JvmStatic
    external fun nextCallEvent(timeoutMs: Long): String?

    /** What the user did at the system's call screen, as JSON. Null, or what went wrong. */
    @JvmStatic
    external fun act(json: String): String?
}
