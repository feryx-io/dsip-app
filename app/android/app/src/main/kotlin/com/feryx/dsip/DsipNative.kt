package com.feryx.dsip

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

    /** A slot in the Rust core for a video tile's surface (VideoTextures.kt, app/rust/src/android_video.rs). */
    @JvmStatic
    external fun videoSlot(): Long

    /** The tile's surface now, or none (null) while Flutter has let it go. */
    @JvmStatic
    external fun videoSurface(slot: Long, surface: android.view.Surface?)

    /** The tile is gone: Dart detached it from the Rust core. */
    @JvmStatic
    external fun videoRelease(slot: Long)

    /** The address of the Rust function that draws a picture on a slot's surface, for Dart to hand the core. */
    @JvmStatic
    external fun videoPresent(): Long
}
