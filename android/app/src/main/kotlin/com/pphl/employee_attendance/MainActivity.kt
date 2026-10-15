package com.pphl.employee_attendance

import android.content.Context
import android.content.Intent
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var apkInstaller: ApkInstallerChannel? = null
    private var voiceTyping: VoiceTypingChannel? = null

    companion object {
        private const val BATTERY_OPTIMIZATION_CHANNEL =
            "com.pphl.employee_attendance/battery_optimization"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apkInstaller = ApkInstallerChannel(this).also { it.register(flutterEngine) }
        voiceTyping = VoiceTypingChannel(this).also { it.register(flutterEngine) }

        // Battery-optimisation status for the geo-tracking screen. The two
        // calls are stateless, so they are registered inline rather than in a
        // channel class; the name and handler shape mirror ApkInstallerChannel.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            BATTERY_OPTIMIZATION_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isIgnoringBatteryOptimizations" -> {
                    val powerManager =
                        getSystemService(Context.POWER_SERVICE) as PowerManager
                    result.success(
                        powerManager.isIgnoringBatteryOptimizations(packageName),
                    )
                }

                "openBatteryOptimizationSettings" -> {
                    startActivity(
                        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
                    )
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
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
