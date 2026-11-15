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

        /** A package name, which is what a real mock-location provider looks like. */
        private val MOCK_PROVIDER_PATTERN = Regex("^[A-Za-z][A-Za-z0-9_.]*$")
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
                "mockLocationStatus" -> result.success(mockLocationStatus())
                "isEmulator" -> result.success(isEmulator())
                // Informational: sent in the event detail so support can tell a
                // developer-options phone from a tampered one.
                "isAdbEnabled" -> result.success(isAdbEnabled())
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Diagnostics for the mock-location probe, never a verdict.
     *
     * Both signals below are unreliable as a blocking test, which is why the app
     * no longer uses them that way. `OPSTR_MOCK_LOCATION` defaults to allowed for
     * an app's own uid on many ROMs, so it reads as "mock location on" on a phone
     * where nobody ever selected a mock app. `mock_location` frequently holds the
     * literal "0" once a provider is cleared, so "non-empty" is not "a provider is
     * set". Only a fix that Android itself flags as mocked may block a punch.
     */
    private fun mockLocationStatus(): Map<String, Any?> {
        val opMode = try {
            val appOps = getSystemService(Context.APP_OPS_SERVICE) as AppOpsManager
            val mode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                appOps.unsafeCheckOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION,
                    Process.myUid(),
                    packageName,
                )
            } else {
                appOps.checkOpNoThrow(
                    AppOpsManager.OPSTR_MOCK_LOCATION,
                    Process.myUid(),
                    packageName,
                )
            }
            when (mode) {
                AppOpsManager.MODE_ALLOWED -> "allowed"
                AppOpsManager.MODE_IGNORED -> "ignored"
                AppOpsManager.MODE_ERRORED -> "errored"
                AppOpsManager.MODE_DEFAULT -> "default"
                else -> "unknown"
            }
        } catch (_: Exception) {
            "unknown"
        }

        val providerPackage = try {
            normalizeMockProviderPackage(
                Settings.Secure.getString(contentResolver, "mock_location"),
            )
        } catch (_: Exception) {
            null
        }

        return mapOf(
            "opMode" to opMode,
            "providerPackage" to providerPackage,
            "adbEnabled" to isAdbEnabled(),
        )
    }

    /**
     * Reduces the raw `mock_location` setting to a package name, or null.
     *
     * ROMs write "", "0", "false" or "null" when nothing is selected, so only a
     * value that actually looks like a package counts.
     */
    private fun normalizeMockProviderPackage(raw: String?): String? {
        val value = raw?.trim().orEmpty()
        if (value.isEmpty()) return null
        if (value == "0" || value.equals("false", true) || value.equals("null", true)) {
            return null
        }
        if (value == packageName) return null
        return if (MOCK_PROVIDER_PATTERN.matches(value)) value else null
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
