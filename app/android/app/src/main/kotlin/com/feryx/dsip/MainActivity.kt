package com.feryx.dsip

import android.Manifest
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** The app's one activity: the Rust core told of the JVM before Dart opens it, and `dsip/mobile` for what the app
 * asks of the phone and the system's call screen (lib/src/mobile/platform.dart). As Anvil's U4a and U4b. */
class MainActivity : FlutterActivity() {
    private var microphoneAnswer: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before Dart opens the library: its audio (cpal's oboe) needs the JVM. The app's calls reach Telecom from here
        // on, Dart or not (A5d-2).
        CoreLink.start(this)
        // Where the app is woken: the token, when built with a push gateway and Firebase.
        Push.register(this)
        super.onCreate(savedInstanceState)
        // Over the lock screen only while there is a call to answer or end.
        CallSystem.onCalls = { any -> overLockScreen(any) }
        overLockScreen(CallSystem.calls.isNotEmpty())
        answerFrom(intent)
    }

    override fun onDestroy() {
        CallSystem.onCalls = null
        super.onDestroy()
    }

    private fun overLockScreen(on: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(on)
            setTurnScreenOn(on)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        answerFrom(intent)
    }

    /** Answer pressed on the call's notification opens the app here. */
    private fun answerFrom(intent: Intent?) {
        if (intent?.action != CallService.ANSWER) return
        // A pushed call's id is below zero (CallSystem.reportPushed).
        val call = intent.getLongExtra(CallService.EXTRA_CALL, Long.MIN_VALUE)
        if (call != Long.MIN_VALUE) CallSystem.emit("answer", call)
        intent.action = null
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsip/mobile")
        CallSystem.channel = channel
        channel.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestMicrophone" -> requestMicrophone(result)
                // AAudio needs nothing set up front: Telecom sets the call's audio mode and routes it.
                "startAudio" -> result.success(null)
                "audioRoutes" -> result.success(CallSystem.audioRoutes())
                "setAudioRoute" -> {
                    CallSystem.setAudioRoute(call.text("route"))
                    result.success(null)
                }
                "setProximity" -> {
                    CallSystem.setProximity(this, call.argument<Boolean>("on") == true)
                    result.success(null)
                }
                "reportIncoming" -> {
                    CallSystem.reportIncoming(this, call.id(), call.text("name"), call.text("address"))
                    result.success(null)
                }
                "reportOutgoing" -> {
                    CallSystem.reportOutgoing(this, call.id(), call.text("name"), call.text("address"))
                    result.success(null)
                }
                "reportConnected" -> {
                    CallSystem.reportConnected(this, call.id())
                    result.success(null)
                }
                "reportEnded" -> {
                    CallSystem.reportEnded(this, call.id())
                    result.success(null)
                }
                // The calls Telecom has now, by id (a pushed call's below zero): what the app's tests look at.
                "systemCalls" -> result.success(CallSystem.calls.keys.toList())
                // A push as FCM delivers one (its `dsip-wake` data), for the app's tests on a device with no Firebase
                // project; debug builds only.
                "deliverPush" -> {
                    if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) {
                        result.notImplemented()
                    } else {
                        Push.handle(this, call.arguments<Map<String, String>>() ?: emptyMap())
                        result.success(null)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        CallSystem.channel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    /** Dart's ints arrive as Integer or Long by size. */
    private fun MethodCall.id(): Long = (argument<Number>("id") ?: -1).toLong()

    private fun MethodCall.text(key: String): String = argument<String>(key) ?: ""

    private fun requestMicrophone(result: MethodChannel.Result) {
        // The call's notification (Android 13 on) is asked for alongside.
        val wanted = buildList {
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) add(Manifest.permission.POST_NOTIFICATIONS)
        }.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (wanted.isEmpty()) {
            result.success(true)
            return
        }
        // One question at a time; an earlier ask still waiting is answered no.
        microphoneAnswer?.success(false)
        microphoneAnswer = result
        requestPermissions(wanted.toTypedArray(), MICROPHONE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MICROPHONE) {
            microphoneAnswer?.success(
                checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED,
            )
            microphoneAnswer = null
        }
    }

    private companion object {
        const val MICROPHONE = 1
    }
}
