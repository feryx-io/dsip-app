package com.thevoiceguy.dsip

import android.content.Context

/** The Rust core, loaded by the app so it knows the JVM and the context (app/rust/src/android.rs). */
object DsipNative {
    init {
        System.loadLibrary("dsip_app_bridge")
    }

    /** Hands the JVM and the application context to the Rust core. */
    @JvmStatic
    external fun init(context: Context)
}
