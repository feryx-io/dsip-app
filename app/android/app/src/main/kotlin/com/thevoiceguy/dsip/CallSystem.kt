package com.thevoiceguy.dsip

import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel

/**
 * The app's calls as Android's Telecom knows them (a self-managed ConnectionService; app plan A5b, as Anvil's U4b):
 * the app reports each call, Telecom keeps the phone's audio and other calling apps in step, and what the user does at
 * the call's notification or a headset comes back as `callEvent`s on `dsip/mobile` (lib/src/mobile/platform.dart).
 */
object CallSystem {
    private const val TAG = "DsipCalls"

    /** A call's handle at Telecom: `dsip:<the other side's DID>`. */
    const val SCHEME = "dsip"
    private val main = Handler(Looper.getMainLooper())

    /** The channel to Dart while the app's engine runs. */
    var channel: MethodChannel? = null

    /** A call: who it is with, and where it is. */
    class Call(val id: Long, val name: String, val address: String, val incoming: Boolean) {
        var connected = false
        var connection: DsipConnection? = null
    }

    val calls = LinkedHashMap<Long, Call>()

    /** Told whenever the calls change: whether there are any. */
    var onCalls: ((Boolean) -> Unit)? = null

    private fun handle(context: Context) =
        PhoneAccountHandle(ComponentName(context, DsipConnectionService::class.java), "dsip")

    private fun telecom(context: Context) = context.getSystemService(Context.TELECOM_SERVICE) as TelecomManager

    private var registered = false

    /** The app's account with Telecom: its own calls, which it shows itself. */
    private fun register(context: Context) {
        if (registered) return
        val account = PhoneAccount.builder(handle(context), context.getString(R.string.app_name))
            .setCapabilities(PhoneAccount.CAPABILITY_SELF_MANAGED)
            .setSupportedUriSchemes(listOf(SCHEME))
            .build()
        telecom(context).registerPhoneAccount(account)
        registered = true
    }

    fun emit(action: String, id: Long, extra: Map<String, Any?> = emptyMap()) {
        val event = HashMap<String, Any?>(extra)
        event["action"] = action
        event["id"] = id
        main.post { channel?.invokeMethod("callEvent", event) }
    }

    private fun extras(call: Call) = Bundle().apply {
        putLong("id", call.id)
        putString("name", call.name)
        putString("address", call.address)
    }

    fun reportIncoming(context: Context, id: Long, name: String, address: String) {
        val call = Call(id, name, address, incoming = true)
        calls[id] = call
        try {
            register(context)
            val telecom = telecom(context)
            if (!telecom.isIncomingCallPermitted(handle(context))) {
                // Another app's call (an emergency call) does not let it ring.
                calls.remove(id)
                emit("failed", id, mapOf("reason" to "busy"))
                return
            }
            val bundle = Bundle().apply { putBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS, extras(call)) }
            telecom.addNewIncomingCall(handle(context), bundle)
        } catch (e: Exception) {
            Log.w(TAG, "Telecom refused the incoming call", e)
            CallService.update(context)
            emit("failed", id, mapOf("reason" to "unavailable"))
        }
    }

    // placeCall on the app's own self-managed account needs MANAGE_OWN_CALLS (in the manifest), not CALL_PHONE, which
    // lint assumes.
    @SuppressLint("MissingPermission")
    fun reportOutgoing(context: Context, id: Long, name: String, address: String) {
        val call = Call(id, name, address, incoming = false)
        calls[id] = call
        try {
            register(context)
            val bundle = Bundle().apply {
                putParcelable(TelecomManager.EXTRA_PHONE_ACCOUNT_HANDLE, handle(context))
                putBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS, extras(call))
            }
            telecom(context).placeCall(Uri.fromParts(SCHEME, address, null), bundle)
        } catch (e: Exception) {
            Log.w(TAG, "Telecom refused the outgoing call", e)
            CallService.update(context)
            emit("failed", id, mapOf("reason" to "unavailable"))
        }
    }

    fun reportConnected(context: Context, id: Long) {
        val call = calls[id] ?: return
        call.connected = true
        call.connection?.setActive()
        CallService.update(context)
    }

    fun reportEnded(context: Context, id: Long) {
        val call = calls.remove(id) ?: return
        call.connection?.let {
            it.setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
            it.destroy()
        }
        CallService.update(context)
    }

    /** Telecom made the call's connection. */
    fun attached(context: Context, connection: DsipConnection) {
        val call = calls[connection.callId]
        if (call == null) {
            // Ended while Telecom was still making it.
            connection.setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
            connection.destroy()
            return
        }
        call.connection = connection
        if (call.connected) connection.setActive()
        CallService.update(context)
        emit("shown", call.id)
    }

    /** Telecom could not make the call's connection. */
    fun refused(context: Context, id: Long) {
        calls.remove(id)
        CallService.update(context)
        emit("failed", id, mapOf("reason" to "unavailable"))
    }
}
