package com.thevoiceguy.dsip

import android.annotation.SuppressLint
import android.content.ComponentName
import android.content.Context
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.OutcomeReceiver
import android.os.PowerManager
import android.os.SystemClock
import android.telecom.CallAudioState
import android.telecom.CallEndpoint
import android.telecom.CallEndpointException
import android.telecom.DisconnectCause
import android.telecom.PhoneAccount
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager
import android.util.Log
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * The app's calls as Android's Telecom knows them (a self-managed ConnectionService; app plan A5b, as Anvil's U4b):
 * the Rust core tells of each call ([fromCore], through [CoreLink]; A5d-2), Telecom keeps the phone's audio and other
 * calling apps in step, and what the user does at the call's notification or a headset goes back to the core — and to
 * Dart, when it runs, as `callEvent`s on `dsip/mobile` (lib/src/mobile/platform.dart).
 *
 * A call a push told of (the Wake Profile, W§5.4) rings at once, before the app has started and bound; the app's call,
 * when the relay flushes its invite, takes its place: the one with the session the wake named.
 */
object CallSystem {
    private const val TAG = "DsipCalls"

    /** A call's handle at Telecom: `dsip:<the other side's DID>`. */
    const val SCHEME = "dsip"
    private val main = Handler(Looper.getMainLooper())

    /** The channel to Dart while the app's engine runs. */
    var channel: MethodChannel? = null

    /** A call: who it is with, and where it is. */
    class Call(var id: Long, var name: String, var address: String, val incoming: Boolean) {
        var connected = false
        var connection: DsipConnection? = null

        /** The DSIP session, as a wake or the app named it. */
        var session: String? = null

        /** Answered at the screen before the app's call came. */
        var answerWhenReady = false

        /** Shown from a push: the app's call not here yet. */
        val pushed get() = id < 0
    }

    /** A pushed call rings this long without the app's call, then stops (T-Establish's maximum, W§5.4). */
    private const val PUSHED_RING_MS = 60_000L

    /** Ids for pushed calls: below zero, apart from the app's. */
    private var nextPushed = -1L

    /** Sessions declined from a push before their invite came: when. */
    private val declined = HashMap<String, Long>()

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

    /** Dart hears what happened at the system, when it runs (its tests do). */
    private fun tell(action: String, id: Long, extra: Map<String, Any?>) {
        val event = HashMap<String, Any?>(extra)
        event["action"] = action
        event["id"] = id
        main.post { channel?.invokeMethod("callEvent", event) }
    }

    /** What the user or the system did with a call: for the core, and Dart. */
    fun emit(action: String, id: Long, extra: Map<String, Any?> = emptyMap()) {
        tell(action, id, extra)
        if (action == "shown") return
        if (id >= 0) {
            CoreLink.act(action, id, extra)
            return
        }
        // A pushed call: the app's is not here yet.
        main.post {
            val call = calls[id] ?: return@post
            when (action) {
                "answer" -> call.answerWhenReady = true
                "end" -> {
                    call.session?.let { decline(it) }
                    CallService.appContext?.let { reportEnded(it, id) }
                }
                // Do Not Disturb or a blocked caller: declined when it comes. Anything else rings on in the
                // notification alone.
                "failed" -> if (extra["reason"] == "filtered") {
                    call.session?.let { decline(it) }
                    CallService.appContext?.let { reportEnded(it, id) }
                }
            }
        }
    }

    private fun decline(session: String) {
        val now = SystemClock.elapsedRealtime()
        declined.entries.removeAll { now - it.value > PUSHED_RING_MS }
        declined[session] = now
    }

    /** What the core says of its calls (`app/rust/src/system.rs`). */
    fun fromCore(context: Context, event: JSONObject) {
        val id = event.optLong("id", -1)
        val name = event.optString("name")
        val address = event.optString("address")
        when (event.optString("kind")) {
            "incoming" -> coreRinging(context, id, name, address, event.optString("session"))
            "outgoing" -> if (!calls.containsKey(id)) reportOutgoing(context, id, name, address)
            "connected" -> reportConnected(context, id)
            "ended" -> reportEnded(context, id)
            // The app stopped: its calls are over; a pushed call waits on.
            "reset" -> calls.values.filter { !it.pushed }.map { it.id }.forEach { reportEnded(context, it) }
        }
    }

    /** The app's call ringing in: the pushed call it is, or a new one. */
    private fun coreRinging(context: Context, id: Long, name: String, address: String, session: String) {
        if (calls.containsKey(id)) return
        if (session.isNotEmpty() && declined.remove(session) != null) {
            CoreLink.act("end", id)
            return
        }
        val pushed = calls.values.firstOrNull { it.pushed && it.session == session }
        if (pushed == null) {
            reportIncoming(context, id, name, address)
            calls[id]?.session = session
            return
        }
        // Who calls, as the verified invite says, in place of the unknown caller (W§6).
        calls.remove(pushed.id)
        pushed.id = id
        pushed.name = name
        pushed.address = address
        calls[id] = pushed
        pushed.connection?.let {
            it.callId = id
            it.setAddress(Uri.fromParts(SCHEME, address, null), TelecomManager.PRESENTATION_ALLOWED)
            it.setCallerDisplayName(name, TelecomManager.PRESENTATION_ALLOWED)
        }
        CallService.update(context)
        if (pushed.answerWhenReady) CoreLink.act("answer", id)
    }

    /** A wake says a call is coming ([session]): it rings now, while the app starts and binds. */
    fun reportPushed(context: Context, session: String, name: String) {
        if (calls.values.any { it.session == session } || declined.containsKey(session)) return
        val id = nextPushed--
        val call = Call(id, name, "", incoming = true)
        call.session = session
        ring(context, call)
        main.postDelayed({
            if (calls[id]?.pushed == true) {
                Log.i(TAG, "the call $session never came")
                reportEnded(context, id)
            }
        }, PUSHED_RING_MS)
    }

    /** A `call-ended` wake: the call a push told of is over before the app bound (W§5.1). */
    fun cancelPushed(context: Context, session: String) {
        val call = calls.values.firstOrNull { it.pushed && it.session == session } ?: return
        reportEnded(context, call.id)
    }

    /** The app could not start: the pushed call cannot reach it. */
    fun wakeFailed(context: Context, session: String) = cancelPushed(context, session)

    // Where a call's audio goes (A5c, as Anvil's U4c): Telecom routes a self-managed call's audio and tells each
    // connection the routes there are (as call endpoints from Android 14, as a CallAudioState before). Kept for Dart as
    // `{current, available, bluetoothName}` (lib/src/mobile/platform.dart).

    private var endpoints: List<CallEndpoint> = emptyList()
    private var routes: Map<String, Any?>? = null

    /** What Dart asks for: the routes now, or null with no call. */
    fun audioRoutes(): Map<String, Any?>? = if (calls.isEmpty()) null else routes

    private fun publish(routes: Map<String, Any?>) {
        if (routes == this.routes) return
        this.routes = routes
        main.post { channel?.invokeMethod("audioRoutes", routes) }
    }

    private fun endpointRoute(type: Int): String? = when (type) {
        CallEndpoint.TYPE_EARPIECE -> "earpiece"
        CallEndpoint.TYPE_SPEAKER -> "speaker"
        CallEndpoint.TYPE_BLUETOOTH -> "bluetooth"
        CallEndpoint.TYPE_WIRED_HEADSET -> "wired"
        else -> null
    }

    /** Android 14 and later: the endpoint in use, and the ones there are. */
    fun endpointsChanged(current: CallEndpoint?, available: List<CallEndpoint>?) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) return
        if (available != null) endpoints = available
        val now = current?.let { endpointRoute(it.endpointType) } ?: (routes?.get("current") as? String) ?: return
        val bluetooth = current?.takeIf { it.endpointType == CallEndpoint.TYPE_BLUETOOTH }
            ?: endpoints.firstOrNull { it.endpointType == CallEndpoint.TYPE_BLUETOOTH }
        publish(
            mapOf(
                "current" to now,
                "available" to endpoints.mapNotNull { endpointRoute(it.endpointType) }.distinct(),
                "bluetoothName" to bluetooth?.endpointName?.toString(),
            ),
        )
    }

    /** Before Android 14: the route in use, and a mask of the ones there are. */
    @Suppress("DEPRECATION")
    fun audioStateChanged(state: CallAudioState) {
        val names = listOf(
            CallAudioState.ROUTE_EARPIECE to "earpiece",
            CallAudioState.ROUTE_SPEAKER to "speaker",
            CallAudioState.ROUTE_BLUETOOTH to "bluetooth",
            CallAudioState.ROUTE_WIRED_HEADSET to "wired",
        )
        val current = names.firstOrNull { it.first == state.route }?.second ?: return
        // A Bluetooth device's name needs BLUETOOTH_CONNECT, which the app does not ask for: "Bluetooth" stands in.
        publish(
            mapOf(
                "current" to current,
                "available" to names.filter { state.supportedRouteMask and it.first != 0 }.map { it.second },
                "bluetoothName" to null,
            ),
        )
    }

    /** Send the calls' audio this way: through any of the app's connections. */
    @Suppress("DEPRECATION")
    fun setAudioRoute(route: String) {
        val connection = calls.values.firstNotNullOfOrNull { it.connection } ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            val endpoint = endpoints.firstOrNull { endpointRoute(it.endpointType) == route } ?: return
            connection.requestCallEndpointChange(
                endpoint,
                { it.run() },
                object : OutcomeReceiver<Void, CallEndpointException> {
                    override fun onResult(result: Void?) {}

                    override fun onError(error: CallEndpointException) {
                        Log.w(TAG, "Telecom did not change the route", error)
                    }
                },
            )
        } else {
            val mask = when (route) {
                "earpiece" -> CallAudioState.ROUTE_EARPIECE
                "speaker" -> CallAudioState.ROUTE_SPEAKER
                "bluetooth" -> CallAudioState.ROUTE_BLUETOOTH
                "wired" -> CallAudioState.ROUTE_WIRED_HEADSET
                else -> return
            }
            connection.setAudioRoute(mask)
        }
    }

    // The screen goes off at the ear (Dart decides when: a call up on the earpiece).
    private var proximity: PowerManager.WakeLock? = null

    // Held for the length of a call, released when Dart says it is over, not within this method (lint's Wakelock rule
    // wants the latter).
    @SuppressLint("Wakelock")
    fun setProximity(context: Context, on: Boolean) {
        val power = context.getSystemService(Context.POWER_SERVICE) as PowerManager
        if (!power.isWakeLockLevelSupported(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK)) return
        val lock = proximity ?: power.newWakeLock(PowerManager.PROXIMITY_SCREEN_OFF_WAKE_LOCK, "dsip:call").also {
            it.setReferenceCounted(false)
            proximity = it
        }
        if (on && !lock.isHeld) {
            // A call longer than this keeps going; the sensor stops at the ear. Only so a lock lost track of cannot
            // hold forever.
            lock.acquire(4 * 60 * 60 * 1000L)
        } else if (!on && lock.isHeld) {
            // Off only once the phone has left the ear.
            lock.release(PowerManager.RELEASE_FLAG_WAIT_FOR_NO_PROXIMITY)
        }
    }

    private fun extras(call: Call) = Bundle().apply {
        putLong("id", call.id)
        putString("name", call.name)
        putString("address", call.address)
    }

    fun reportIncoming(context: Context, id: Long, name: String, address: String) {
        ring(context, Call(id, name, address, incoming = true))
    }

    private fun ring(context: Context, call: Call) {
        val id = call.id
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

    /** Calls ended while Telecom was still making their connection: told as shown when it comes, then ended. */
    private val endedUnattached = HashSet<Long>()

    fun reportEnded(context: Context, id: Long) {
        val call = calls.remove(id) ?: return
        if (call.connection == null) endedUnattached.add(id)
        call.connection?.let {
            it.setDisconnected(DisconnectCause(DisconnectCause.LOCAL))
            it.destroy()
        }
        if (calls.isEmpty()) {
            routes = null
            endpoints = emptyList()
        }
        CallService.update(context)
    }

    /** Telecom made the call's connection. */
    fun attached(context: Context, connection: DsipConnection) {
        val call = calls[connection.callId]
        if (call == null) {
            // Ended while Telecom was still making it (a pushed call whose app could not start, a call cancelled at
            // once): it was shown, for an instant, and is gone. Every call handed to Telecom is told as shown or
            // failed, so whoever follows the calls never waits on one.
            if (endedUnattached.remove(connection.callId)) emit("shown", connection.callId)
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
        if (endedUnattached.remove(id)) {
            emit("failed", id, mapOf("reason" to "unavailable"))
            return
        }
        calls.remove(id)
        CallService.update(context)
        emit("failed", id, mapOf("reason" to "unavailable"))
    }
}
