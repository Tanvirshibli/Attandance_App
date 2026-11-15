package com.pphl.employee_attendance

import android.os.Build
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyPermanentlyInvalidatedException
import android.security.keystore.KeyProperties
import android.util.Base64
import androidx.biometric.BiometricManager
import androidx.biometric.BiometricPrompt
import androidx.core.content.ContextCompat
import androidx.fragment.app.FragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.InvalidKeyException
import java.security.KeyPairGenerator
import java.security.KeyStore
import java.security.PrivateKey
import java.security.Signature
import java.security.spec.ECGenParameterSpec

/**
 * Fingerprint sign-in backed by an Android Keystore key.
 *
 * Android does not expose fingerprint templates to apps, so there is nothing to
 * enrol or upload. What is enrolled instead is the public half of an ECDSA
 * P-256 key whose private half only signs after the device's own fingerprint
 * prompt. The backend stores the public key and verifies the signature on a
 * nonce it issued.
 *
 * The prompt is hosted by a FragmentActivity and only one may be in flight at a
 * time; a second `sign` while one is showing is rejected rather than queued.
 */
class BiometricKeystoreChannel(
    private val activity: FragmentActivity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.pphl.attendance/biometric_keystore"
        private const val KEYSTORE = "AndroidKeyStore"
        private const val PROMPT_TITLE = "Fingerprint verification"
        private const val PROMPT_SUBTITLE = "Confirm it's you to continue"
    }

    private var pendingResult: MethodChannel.Result? = null
    private var pendingData: ByteArray? = null

    fun register(flutterEngine: FlutterEngine) {
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler(this)
    }

    fun dispose() {
        pendingResult?.error(
            "auth_failed",
            "The screen closed before fingerprint verification finished.",
            null,
        )
        pendingResult = null
        pendingData = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "canAuthenticate" -> result.success(canAuthenticate())

            "generateKey" -> {
                val alias = call.argument<String>("alias")
                if (alias.isNullOrBlank()) {
                    result.error("invalid_arguments", "alias is required", null)
                    return
                }
                try {
                    generateKey(alias)
                    result.success(true)
                } catch (error: Exception) {
                    result.error("crypto_failed", describe(error), null)
                }
            }

            "getPublicKey" -> {
                val alias = call.argument<String>("alias")
                if (alias.isNullOrBlank()) {
                    result.error("invalid_arguments", "alias is required", null)
                    return
                }
                result.success(readPublicKey(alias))
            }

            "sign" -> sign(call, result)

            "hasKey" -> {
                val alias = call.argument<String>("alias")
                result.success(!alias.isNullOrBlank() && hasKey(alias))
            }

            "deleteKey" -> {
                val alias = call.argument<String>("alias")
                if (!alias.isNullOrBlank()) {
                    deleteKey(alias)
                }
                result.success(true)
            }

            else -> result.notImplemented()
        }
    }

    private fun canAuthenticate(): Map<String, Any> {
        val manager = BiometricManager.from(activity)
        return when (manager.canAuthenticate(BiometricManager.Authenticators.BIOMETRIC_STRONG)) {
            BiometricManager.BIOMETRIC_SUCCESS ->
                mapOf("available" to true, "reason" to "Ready", "code" to "available")

            BiometricManager.BIOMETRIC_ERROR_NO_HARDWARE ->
                unavailable("This phone has no fingerprint sensor.", "unavailable")

            BiometricManager.BIOMETRIC_ERROR_HW_UNAVAILABLE ->
                unavailable("The fingerprint sensor is busy right now. Try again in a moment.", "unavailable")

            BiometricManager.BIOMETRIC_ERROR_NONE_ENROLLED ->
                unavailable("No fingerprint is set up in this phone's settings. Add one there first.", "none_enrolled")

            BiometricManager.BIOMETRIC_ERROR_SECURITY_UPDATE_REQUIRED ->
                unavailable("A security update is required before fingerprints can be used.", "unavailable")

            BiometricManager.BIOMETRIC_ERROR_UNSUPPORTED ->
                unavailable("This phone's fingerprint hardware is not supported.", "unavailable")

            else -> unavailable("Fingerprint sign-in is unavailable on this device.", "unknown")
        }
    }

    private fun unavailable(reason: String, code: String): Map<String, Any> =
        mapOf("available" to false, "reason" to reason, "code" to code)

    private fun generateKey(alias: String) {
        val keyStore = loadKeyStore()
        if (keyStore.containsAlias(alias)) {
            keyStore.deleteEntry(alias)
        }

        val builder = KeyGenParameterSpec.Builder(alias, KeyProperties.PURPOSE_SIGN)
            .setAlgorithmParameterSpec(ECGenParameterSpec("secp256r1"))
            .setDigests(KeyProperties.DIGEST_SHA256)
            .setUserAuthenticationRequired(true)
            // A new fingerprint in the phone's settings must not be able to use
            // a key the previous owner enrolled.
            .setInvalidatedByBiometricEnrollment(true)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            // Auth-per-use: every signature needs a fresh biometric prompt.
            builder.setUserAuthenticationParameters(
                0,
                KeyProperties.AUTH_BIOMETRIC_STRONG,
            )
        } else {
            @Suppress("DEPRECATION")
            builder.setUserAuthenticationValidityDurationSeconds(-1)
        }

        val generator = KeyPairGenerator.getInstance(
            KeyProperties.KEY_ALGORITHM_EC,
            KEYSTORE,
        )
        generator.initialize(builder.build())
        generator.generateKeyPair()
    }

    private fun readPublicKey(alias: String): String? {
        val certificate = try {
            loadKeyStore().getCertificate(alias)
        } catch (_: Exception) {
            null
        } ?: return null
        return Base64.encodeToString(certificate.publicKey.encoded, Base64.NO_WRAP)
    }

    private fun hasKey(alias: String): Boolean = try {
        loadKeyStore().containsAlias(alias)
    } catch (_: Exception) {
        false
    }

    private fun deleteKey(alias: String) {
        try {
            val keyStore = loadKeyStore()
            if (keyStore.containsAlias(alias)) {
                keyStore.deleteEntry(alias)
            }
        } catch (_: Exception) {
            // Nothing to delete.
        }
    }

    private fun sign(call: MethodCall, result: MethodChannel.Result) {
        val alias = call.argument<String>("alias")
        val data = call.argument<String>("data")
        if (alias.isNullOrBlank() || data.isNullOrBlank()) {
            result.error("invalid_arguments", "alias and data are required", null)
            return
        }

        if (pendingResult != null) {
            result.error("auth_failed", "A fingerprint prompt is already showing.", null)
            return
        }

        val signature = try {
            val keyStore = loadKeyStore()
            val privateKey = keyStore.getKey(alias, null) as? PrivateKey
            if (privateKey == null) {
                result.error("key_invalidated", "The fingerprint key is missing on this device.", null)
                return
            }
            Signature.getInstance("SHA256withECDSA").apply { initSign(privateKey) }
        } catch (error: InvalidKeyException) {
            if (error is KeyPermanentlyInvalidatedException ||
                error.cause is KeyPermanentlyInvalidatedException
            ) {
                result.error(
                    "key_invalidated",
                    "The fingerprint set changed, so the saved key was disabled.",
                    null,
                )
            } else {
                result.error("crypto_failed", describe(error), null)
            }
            return
        } catch (error: Exception) {
            result.error("crypto_failed", describe(error), null)
            return
        }

        // Decode before latching, so a malformed payload cannot leave a pending
        // result that nothing will ever complete.
        val decoded = try {
            Base64.decode(data, Base64.DEFAULT)
        } catch (error: Exception) {
            result.error("invalid_arguments", "data must be base64", null)
            return
        }

        pendingData = decoded
        pendingResult = result
        // A prompt that cannot even be raised (a finishing activity, an OEM
        // BiometricPrompt that throws) must not leave the latch set: one throw
        // here used to make every later sign fail with "a fingerprint prompt is
        // already showing" for the rest of the process's life.
        activity.runOnUiThread {
            try {
                showPrompt(signature)
            } catch (error: Exception) {
                finishError("auth_failed", describe(error))
            }
        }
    }

    private fun showPrompt(signature: Signature) {
        val prompt = BiometricPrompt(
            activity,
            ContextCompat.getMainExecutor(activity),
            object : BiometricPrompt.AuthenticationCallback() {
                override fun onAuthenticationSucceeded(
                    result: BiometricPrompt.AuthenticationResult,
                ) {
                    // The key is auth-per-use, so the data is fed to the
                    // signature only after the prompt has authorised it.
                    val authenticated = result.cryptoObject?.signature ?: signature
                    try {
                        authenticated.update(pendingData ?: ByteArray(0))
                        val signed = authenticated.sign()
                        finishSuccess(Base64.encodeToString(signed, Base64.NO_WRAP))
                    } catch (error: Exception) {
                        finishError("crypto_failed", describe(error))
                    }
                }

                override fun onAuthenticationError(
                    errorCode: Int,
                    errString: CharSequence,
                ) {
                    finishError(errorCodeFor(errorCode), errString.toString())
                }
            },
        )

        prompt.authenticate(
            BiometricPrompt.PromptInfo.Builder()
                .setTitle(PROMPT_TITLE)
                .setSubtitle(PROMPT_SUBTITLE)
                .setNegativeButtonText("Cancel")
                .setAllowedAuthenticators(BiometricManager.Authenticators.BIOMETRIC_STRONG)
                .build(),
            BiometricPrompt.CryptoObject(signature),
        )
    }

    private fun finishSuccess(signature: String) {
        val result = pendingResult ?: return
        pendingResult = null
        pendingData = null
        result.success(signature)
    }

    private fun finishError(code: String, message: String) {
        val result = pendingResult ?: return
        pendingResult = null
        pendingData = null
        result.error(code, message, null)
    }

    private fun errorCodeFor(errorCode: Int): String = when (errorCode) {
        BiometricPrompt.ERROR_USER_CANCELED,
        BiometricPrompt.ERROR_NEGATIVE_BUTTON,
        BiometricPrompt.ERROR_CANCELED -> "user_canceled"

        BiometricPrompt.ERROR_LOCKOUT,
        BiometricPrompt.ERROR_LOCKOUT_PERMANENT -> "lockout"

        BiometricPrompt.ERROR_NO_BIOMETRICS -> "none_enrolled"

        BiometricPrompt.ERROR_HW_NOT_PRESENT,
        BiometricPrompt.ERROR_HW_UNAVAILABLE -> "unavailable"

        else -> "auth_failed"
    }

    private fun loadKeyStore(): KeyStore =
        KeyStore.getInstance(KEYSTORE).apply { load(null) }

    private fun describe(error: Exception): String =
        error.message ?: error.javaClass.simpleName
}
