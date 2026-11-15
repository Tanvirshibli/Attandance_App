package com.pphl.employee_attendance

import android.app.AppOpsManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.PowerManager
import android.os.Process
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

// FlutterFragmentActivity, not FlutterActivity: BiometricPrompt is hosted by a
// FragmentActivity, and the fingerprint channel shows it directly.
class MainActivity : FlutterFragmentActivity() {
    private var apkInstaller: ApkInstallerChannel? = null
    private var voiceTyping: VoiceTypingChannel? = null
    private var biometricKeystore: BiometricKeystoreChannel? = null

    companion object {
        private const val BATTERY_OPTIMIZATION_CHANNEL =
            "com.pphl.employee_attendance/battery_optimization"

        private const val DEVICE_INTEGRITY_CHANNEL =
            "com.pphl.attendance/device_integrity"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        apkInstaller = ApkInstallerChannel(this).also { it.register(flutterEngine) }
        voiceTyping = VoiceTypingChannel(this).also { it.register(flutterEngine) }
        biometricKeystore =
            BiometricKeystoreChannel(this).also { it.register(flutterEngine) }

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

        // Attendance integrity. Three stateless questions the Dart side asks
        // before it will stamp a punch, so they are registered inline next to
        // the battery channel rather than in a class of their own. The
        // biometric channel above is registered by its own class and is not
        // touched here.
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            DEVICE_INTEGRITY_CHANNEL,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "isMockLocationEnabled" -> result.success(isMockLocationEnabled())
                "isEmulator" -> result.success(isEmulator())
                // Informational: sent in the event detail so support can tell a
                // developer-options phone from a tampered one.
                "isAdbEnabled" -> result.success(isAdbEnabled())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Whether mock locations can currently reach this app.
     *
     * Two independent signals, because they catch different attackers:
     *
     *  - `OPSTR_MOCK_LOCATION` checked against this app's own uid. That is the
     *    per-app AppOps switch a developer turns on, and it is what matters when
     *    *this* app is the one calling a mock provider.
     *  - `Settings.Secure["mock_location"]`. That key holds the package name of
     *    the app currently installed as the system's mock-location provider, and
     *    it is what matters when a separate fake-GPS app is feeding positions to
     *    every app on the phone.
     *
     * Anything that throws is reported as "not enabled": a settings read failing
     * must not turn into a block on an honest employee.
     */
    private fun isMockLocationEnabled(): Boolean {
        try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = appOps.checkOpNoThrow(
                AppOpsManager.OPSTR_MOCK_LOCATION,
                Process.myUid(),
                packageName,
            )
            if (mode == AppOpsManager.MODE_ALLOWED) return true
        } catch (_: Exception) {
            // Fall through to the provider check.
        }

        return try {
            val provider = Settings.Secure.getString(contentResolver, "mock_location")
            // Some ROMs store the literal string "null" once the provider is
            // cleared, so a non-empty value is not enough on its own.
            !provider.isNullOrBlank() && !provider.equals("null", ignoreCase = true)
        } catch (_: Exception) {
            false
        }
    }

    /** Developer options / USB debugging left on. Context for the event only. */
    private fun isAdbEnabled(): Boolean = try {
        Settings.Global.getInt(contentResolver, Settings.Global.ADB_ENABLED, 0) == 1
    } catch (_: Exception) {
        false
    }

    /**
     * Build-fingerprint heuristics for an emulator.
     *
     * Only used to *exempt* a build compiled with
     * `--dart-define=ALLOW_EMULATOR_SPOOF=true`; a production build ignores the
     * answer entirely, so a wrong verdict here cannot weaken anything.
     */
    private fun isEmulator(): Boolean = try {
        Build.FINGERPRINT.startsWith("generic", ignoreCase = true) ||
            Build.FINGERPRINT.contains("emulator", ignoreCase = true) ||
            Build.HARDWARE.contains("goldfish", ignoreCase = true) ||
            Build.HARDWARE.contains("ranchu", ignoreCase = true) ||
            Build.MODEL.contains("sdk", ignoreCase = true) ||
            Build.MODEL.contains("emulator", ignoreCase = true)
    } catch (_: Exception) {
        false
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
        biometricKeystore?.dispose()
        biometricKeystore = null
        super.onDestroy()
    }
}
