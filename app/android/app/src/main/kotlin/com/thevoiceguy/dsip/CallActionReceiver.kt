package com.thevoiceguy.dsip

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/** Decline or Hang up pressed on the call's notification. */
class CallActionReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != CallService.END) return
        // A pushed call's id is below zero (CallSystem.reportPushed).
        val call = intent.getLongExtra(CallService.EXTRA_CALL, Long.MIN_VALUE)
        if (call != Long.MIN_VALUE) CallSystem.emit("end", call)
    }
}
