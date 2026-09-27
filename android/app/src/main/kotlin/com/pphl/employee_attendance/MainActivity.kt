package com.pphl.employee_attendance

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var apkInstaller: ApkInstallerChannel? = null
    private var voiceTyping: VoiceTypingChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apkInstaller = ApkInstallerChannel(this).also { it.register(flutterEngine) }
        voiceTyping = VoiceTypingChannel(this).also { it.register(flutterEngine) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (voiceTyping?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        voiceTyping?.dispose()
        voiceTyping = null
        super.onDestroy()
    }
}
