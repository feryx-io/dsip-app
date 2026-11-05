package com.thevoiceguy.dsip

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/** The app's one activity: the Rust core told of the JVM before Dart opens it, and `dsip/mobile` for what the app
 * asks of the phone (lib/src/mobile/platform.dart). As Anvil's U4a. */
class MainActivity : FlutterActivity() {
    private var microphoneAnswer: MethodChannel.Result? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        // Before Dart opens the library: its audio (cpal's oboe) needs the JVM.
        DsipNative.init(applicationContext)
        super.onCreate(savedInstanceState)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "dsip/mobile")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestMicrophone" -> requestMicrophone(result)
                    // AAudio needs nothing set up front; the call's audio mode comes with the system's call
                    // screen (A5b).
                    "startAudio" -> result.success(null)
                    else -> result.notImplemented()
                }
            }
    }

    private fun requestMicrophone(result: MethodChannel.Result) {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) {
            result.success(true)
            return
        }
        // One question at a time; an earlier ask still waiting is answered no.
        microphoneAnswer?.success(false)
        microphoneAnswer = result
        requestPermissions(arrayOf(Manifest.permission.RECORD_AUDIO), MICROPHONE)
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == MICROPHONE) {
            microphoneAnswer?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            microphoneAnswer = null
        }
    }

    private companion object {
        const val MICROPHONE = 1
    }
}
