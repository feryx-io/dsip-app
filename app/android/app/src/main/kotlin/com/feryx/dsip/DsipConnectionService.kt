package com.feryx.dsip

import android.net.Uri
import android.os.Build
import android.telecom.CallAudioState
import android.telecom.CallEndpoint
import android.telecom.Connection
import android.telecom.ConnectionRequest
import android.telecom.ConnectionService
import android.telecom.DisconnectCause
import android.telecom.PhoneAccountHandle
import android.telecom.TelecomManager

/** One of the app's calls as Telecom holds it. DSIP's calls have no hold and no keys: muting is all it offers. */
class DsipConnection(var callId: Long, name: String, address: String) : Connection() {
    init {
        connectionProperties = PROPERTY_SELF_MANAGED
        connectionCapabilities = CAPABILITY_MUTE
        audioModeIsVoip = true
        setAddress(Uri.fromParts(CallSystem.SCHEME, address, null), TelecomManager.PRESENTATION_ALLOWED)
        setCallerDisplayName(name, TelecomManager.PRESENTATION_ALLOWED)
    }

    override fun onAnswer() = CallSystem.emit("answer", callId)

    override fun onAnswer(videoState: Int) = onAnswer()

    override fun onReject() = CallSystem.emit("end", callId)

    override fun onDisconnect() = CallSystem.emit("end", callId)

    override fun onAbort() = CallSystem.emit("end", callId)

    // Where the call's audio goes (A5c).
    override fun onCallEndpointChanged(callEndpoint: CallEndpoint) = CallSystem.endpointsChanged(callEndpoint, null)

    override fun onAvailableCallEndpointsChanged(availableEndpoints: List<CallEndpoint>) =
        CallSystem.endpointsChanged(null, availableEndpoints)

    @Deprecated("Android 14 tells of call endpoints instead")
    override fun onCallAudioStateChanged(state: CallAudioState) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            @Suppress("DEPRECATION")
            CallSystem.audioStateChanged(state)
        }
    }

    /** A self-managed call shows its own incoming screen: the notification. */
    override fun onShowIncomingCallUi() {
        CallService.appContext?.let { CallService.update(it) }
    }
}

/** Telecom's way to the app's calls (self-managed: the app shows them). */
class DsipConnectionService : ConnectionService() {
    private fun make(request: ConnectionRequest): DsipConnection? {
        // Telecom hands the app's own extras over as the request's; some versions leave them nested under the key they
        // were sent with.
        val outer = request.extras ?: return null
        val extras = listOf(
            outer,
            outer.getBundle(TelecomManager.EXTRA_INCOMING_CALL_EXTRAS),
            outer.getBundle(TelecomManager.EXTRA_OUTGOING_CALL_EXTRAS),
        ).firstOrNull { it?.containsKey("id") == true } ?: return null
        return DsipConnection(extras.getLong("id"), extras.getString("name") ?: "", extras.getString("address") ?: "")
    }

    override fun onCreateIncomingConnection(account: PhoneAccountHandle?, request: ConnectionRequest): Connection {
        CallService.appContext = applicationContext
        val connection = make(request) ?: return Connection.createFailedConnection(DisconnectCause(DisconnectCause.ERROR))
        connection.setRinging()
        CallSystem.attached(applicationContext, connection)
        return connection
    }

    override fun onCreateOutgoingConnection(account: PhoneAccountHandle?, request: ConnectionRequest): Connection {
        CallService.appContext = applicationContext
        val connection = make(request) ?: return Connection.createFailedConnection(DisconnectCause(DisconnectCause.ERROR))
        connection.setDialing()
        CallSystem.attached(applicationContext, connection)
        return connection
    }

    override fun onCreateIncomingConnectionFailed(account: PhoneAccountHandle?, request: ConnectionRequest) {
        make(request)?.let { CallSystem.refused(applicationContext, it.callId) }
    }

    override fun onCreateOutgoingConnectionFailed(account: PhoneAccountHandle?, request: ConnectionRequest) {
        make(request)?.let { CallSystem.refused(applicationContext, it.callId) }
    }
}
