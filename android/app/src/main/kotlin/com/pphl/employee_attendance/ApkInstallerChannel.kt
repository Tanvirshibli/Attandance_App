package com.pphl.employee_attendance

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class ApkInstallerChannel(
    private val activity: MainActivity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.pphl.employee_attendance/apk_installer"
    }

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getPreferredAbi" -> {
                val abis = Build.SUPPORTED_ABIS?.toList().orEmpty()
                val preferred = when {
                    abis.contains("arm64-v8a") -> "arm64-v8a"
                    abis.contains("armeabi-v7a") -> "armeabi-v7a"
                    abis.contains("x86_64") -> "x86_64"
                    else -> abis.firstOrNull() ?: "arm64-v8a"
                }
                result.success(preferred)
            }

            "installApk" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("invalid_path", "APK path is required", null)
                    return
                }
                try {
                    installApk(path)
                    result.success(null)
                } catch (e: Exception) {
                    result.error("install_failed", e.message, null)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun installApk(path: String) {
        val file = File(path)
        if (!file.exists()) {
            throw IllegalStateException("APK file not found")
        }

        val uri: Uri = FileProvider.getUriForFile(
            activity,
            "${activity.packageName}.fileprovider",
            file,
        )

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        activity.startActivity(intent)
    }
}
