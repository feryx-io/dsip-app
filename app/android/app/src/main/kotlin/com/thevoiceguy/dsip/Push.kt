package com.thevoiceguy.dsip

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import org.json.JSONObject

/**
 * The app woken while it sleeps through Firebase Cloud Messaging (app plan A5d-2; the Wake Profile, W§5): the core
 * enrols the FCM token at the publisher's push gateway and registers with its relay and mailbox; a relay holding a
 * call for the app wakes it. A call push rings at once — Telecom and the call's notification — while the app starts
 * and binds, and the call's invite, flushed to it then, takes the ringing call's place ([CallSystem]).
 *
 * The gateway and the Firebase project are the publisher's, given at build time (`DSIP_PUSH_GATEWAY`, `DSIP_FCM_*`,
 * app/android/app/build.gradle.kts); an app built without them is never woken.
 */
object Push {
    private const val TAG = "DsipPush"
    private val main = Handler(Looper.getMainLooper())

    /** The Firebase project this build pushes through, if it has one and a gateway to push it. */
    private fun project(context: Context): String? {
        if (CoreLink.gateway(context).isEmpty()) return null
        return FirebaseApp.getApps(context).firstOrNull()?.options?.projectId
    }

    /** Ask Firebase for this install's token, and give it to the core. */
    fun register(context: Context) {
        val app = context.applicationContext
        val project = project(app) ?: return
        FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
            if (task.isSuccessful) {
                CoreLink.setPush(app, "fcm", project, task.result)
            } else {
                // No Google Play services, or no network yet: asked again at the app's next start.
                Log.w(TAG, "no FCM token", task.exception)
            }
        }
    }

    /** Firebase renewed the token. */
    fun tokenChanged(context: Context, token: String) {
        val project = project(context) ?: return
        CoreLink.setPush(context, "fcm", project, token)
    }

    /**
     * A push's data: `dsip-wake`, the wake as a JSON string (W§5.3). Its `sealed` hint is not opened here: the app
     * knows no names for DIDs, and what the hint says is the relay's claim (W§6), so the call rings as from an unknown
     * caller until its verified invite says who.
     */
    fun handle(context: Context, data: Map<String, String>) {
        val app = context.applicationContext
        val wake = try {
            JSONObject(data["dsip-wake"] ?: return)
        } catch (e: Exception) {
            Log.w(TAG, "a push that is not a wake", e)
            return
        }
        val session = wake.optString("session")
        main.post {
            // Not set up since the token was given: nothing to wake.
            if (!CoreLink.configured(app)) {
                Log.i(TAG, "a wake for an app not set up")
                return@post
            }
            when (wake.optString("kind")) {
                "call" -> {
                    if (session.isEmpty()) return@post
                    CoreLink.start(app)
                    CallSystem.reportPushed(app, session, app.getString(R.string.wake_caller))
                    CoreLink.wake(app) { CallSystem.wakeFailed(app, session) }
                }
                // The invite stopped being held before the app bound: the call ends on the screen (W§5.1).
                "call-ended" -> CallSystem.cancelPushed(app, session)
                // `message`, and kinds this app does not know (W§5.2): the app starts and its mailbox delivers.
                else -> CoreLink.wake(app) {}
            }
        }
    }
}

/** Where FCM delivers the app's pushes and its new tokens. */
class DsipMessagingService : FirebaseMessagingService() {
    override fun onMessageReceived(message: RemoteMessage) = Push.handle(this, message.data)

    override fun onNewToken(token: String) = Push.tokenChanged(applicationContext, token)
}
