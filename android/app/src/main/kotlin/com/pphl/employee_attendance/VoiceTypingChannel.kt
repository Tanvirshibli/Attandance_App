package com.pphl.employee_attendance

import android.Manifest
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.speech.RecognitionListener
import android.speech.RecognizerIntent
import android.speech.SpeechRecognizer
import androidx.core.app.ActivityCompat
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Drives [SpeechRecognizer] directly instead of going through `speech_to_text`.
 *
 * The Flutter plugin forwards `localeId`, `partialResults`, `listenMode`,
 * `onDevice` and `pauseFor`, but silently drops `contextualPhrases` and
 * `listenFor` on Android — its `listen` handler never unpacks them. That removes
 * the two levers that matter most for Bangla accuracy: in-vocabulary biasing via
 * `EXTRA_SPEECH_INPUT_PHRASES`, and `EXTRA_ENABLE_FORMATTING`.
 *
 * This channel also keeps the recognizer alive across silences. The recognizer
 * ends a session on its own after a pause; without a re-arm the tail of a long
 * dictation is lost. Here the session restarts and accumulates instead, which is
 * the main reason keyboard-grade dictation keeps flowing.
 */
class VoiceTypingChannel(
    private val activity: MainActivity,
) : MethodChannel.MethodCallHandler {

    companion object {
        const val CHANNEL = "com.pphl.employee_attendance/voice_typing"
        private const val PERMISSION_REQUEST_CODE = 9317
        private const val RESTART_DELAY_MS = 250L
        private const val LOCALE_QUERY_TIMEOUT_MS = 1500L
        private const val MAX_EMPTY_RESTARTS = 8
        private const val MAX_ALTERNATES = 5
        private const val ACTION_GET_LANGUAGE_DETAILS =
            "com.google.android.speech.action.GET_LANGUAGE_DETAILS"

        // Not exposed as RecognizerIntent constants. Both are consumed by the
        // Google recognizer purely as intent extras, and any engine that does
        // not know them ignores them.
        private const val EXTRA_SPEECH_INPUT_PHRASES =
            "android.speech.extra.SPEECH_INPUT_PHRASES"
        private const val EXTRA_ENABLE_FORMATTING =
            "android.speech.extra.ENABLE_FORMATTING"
        private const val EXTRA_ENABLE_LANGUAGE_DETECTION =
            "android.speech.extra.ENABLE_LANGUAGE_DETECTION"
    }

    private val context: Context get() = activity
    private val handler = Handler(Looper.getMainLooper())

    private var speechRecognizer: SpeechRecognizer? = null
    private var channel: MethodChannel? = null

    private var sessionActive = false
    private var stopRequested = false
    private var busy = false
    private var startedAt = 0L

    private var locale = "en-US"
    private var phrases: List<String> = emptyList()
    private var pauseMillis = 2500
    private var maxMillis = 180_000L

    private val transcript = StringBuilder()
    private var emptyRestarts = 0
    private var pendingListen: MethodChannel.Result? = null

    fun register(flutterEngine: FlutterEngine) {
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .also { it.setMethodCallHandler(this) }
    }

    fun dispose() {
        sessionActive = false
        busy = false
        stopRequested = true
        handler.removeCallbacksAndMessages(null)
        speechRecognizer?.destroy()
        speechRecognizer = null
        channel?.setMethodCallHandler(null)
    }

    fun onRequestPermissionsResult(requestCode: Int, grantResults: IntArray): Boolean {
        if (requestCode != PERMISSION_REQUEST_CODE) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        val pending = pendingListen
        pendingListen = null
        if (granted) {
            startListening(pending)
        } else {
            pending?.error(
                "permission_denied",
                "Microphone permission is required for voice typing.",
                null,
            )
        }
        return true
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> result.success(isUsable())

            "supportedLocales" -> querySupportedLocales(result)

            "listen" -> {
                if (!isUsable()) {
                    result.error(
                        "not_available",
                        "No speech recognition service is available on this device.",
                        null,
                    )
                    return
                }
                locale = call.argument<String>("locale") ?: locale
                phrases = call.argument<List<String>>("phrases").orEmpty()
                pauseMillis = call.argument<Int>("pauseMillis") ?: pauseMillis
                maxMillis = (call.argument<Int>("maxMillis") ?: 180_000).toLong()

                if (!hasRecordPermission()) {
                    pendingListen = result
                    ActivityCompat.requestPermissions(
                        activity,
                        arrayOf(Manifest.permission.RECORD_AUDIO),
                        PERMISSION_REQUEST_CODE,
                    )
                    return
                }
                startListening(result)
            }

            "stop" -> {
                stopRequested = true
                if (busy) {
                    speechRecognizer?.stopListening()
                } else {
                    endSession(emitFinal = true)
                }
                result.success(null)
            }

            "cancel" -> {
                stopRequested = true
                speechRecognizer?.cancel()
                endSession(emitFinal = false)
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    private fun isUsable(): Boolean = try {
        SpeechRecognizer.isRecognitionAvailable(context)
    } catch (e: Exception) {
        false
    }

    /**
     * BCP-47 tags the active recognizer reports, delivered asynchronously.
     *
     * This is the most accurate availability signal available: it comes from the
     * engine itself rather than from the installed on-device language packs, so a
     * device without a `bn` pack but with online recognition still reports Bangla
     * as usable. Answered by broadcast on every supported release, so the result
     * is always delivered asynchronously on the main thread.
     */
    private fun querySupportedLocales(result: MethodChannel.Result) {
        val recognizer = try {
            SpeechRecognizer.createSpeechRecognizer(context)
        } catch (e: Exception) {
            result.success(emptyList<String>())
            return
        }
        val tags = mutableListOf<String>()

        var timeoutRunnable: Runnable? = null
        var receiver: android.content.BroadcastReceiver? = null

        fun unregister() {
            val pending = receiver
            if (pending == null) return
            receiver = null
            try {
                context.unregisterReceiver(pending)
            } catch (e: Exception) {
                // Never registered, or already gone.
            }
        }

        var answered = false
        fun finish() {
            if (answered) return
            answered = true
            timeoutRunnable?.let { handler.removeCallbacks(it) }
            result.success(ArrayList(tags))
        }

        receiver = object : android.content.BroadcastReceiver() {
            override fun onReceive(ctx: Context?, intent: Intent?) {
                intent?.getStringArrayListExtra(
                    RecognizerIntent.EXTRA_SUPPORTED_LANGUAGES,
                )?.forEach { tags.add(it) }
                unregister()
                finish()
            }
        }

        timeoutRunnable = Runnable {
            unregister()
            finish()
        }

        recognizer.destroy()

        val filter = IntentFilter(ACTION_GET_LANGUAGE_DETAILS)

        // The broadcast query is the only reliable source of the full online
        // language list; `availableOnDeviceLanguages` reflects offline packs only,
        // so it is deliberately not used here.
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.registerReceiver(receiver, filter, Context.RECEIVER_EXPORTED)
            } else {
                @Suppress("UnspecifiedRegisterReceiverFlag")
                context.registerReceiver(receiver, filter)
            }
        } catch (e: Exception) {
            receiver = null
            finish()
            return
        }
        handler.postDelayed(timeoutRunnable, LOCALE_QUERY_TIMEOUT_MS)
    }

    private fun hasRecordPermission(): Boolean =
        ActivityCompat.checkSelfPermission(
            context,
            Manifest.permission.RECORD_AUDIO,
        ) == PackageManager.PERMISSION_GRANTED

    private fun startListening(result: MethodChannel.Result?) {
        handler.post {
            if (!sessionActive) {
                transcript.setLength(0)
                emptyRestarts = 0
                stopRequested = false
                startedAt = System.currentTimeMillis()
                sessionActive = true
            }

            if (speechRecognizer == null) {
                if (!createRecognizer()) {
                    sessionActive = false
                    result?.error(
                        "not_available",
                        "Speech recognizer could not be created.",
                        null,
                    )
                    return@post
                }
            }

            busy = true
            try {
                speechRecognizer?.startListening(buildIntent())
                emitStatus("listening")
                result?.success(true)
            } catch (e: Exception) {
                busy = false
                sessionActive = false
                result?.error("listen_failed", e.message, null)
            }
        }
    }

    private fun createRecognizer(): Boolean = try {
        speechRecognizer?.destroy()
        speechRecognizer = SpeechRecognizer.createSpeechRecognizer(context).apply {
            setRecognitionListener(listener)
        }
        true
    } catch (e: Exception) {
        speechRecognizer = null
        false
    }

    private fun buildIntent(): Intent = Intent(RecognizerIntent.ACTION_RECOGNIZE_SPEECH).apply {
        putExtra(RecognizerIntent.EXTRA_LANGUAGE_MODEL, RecognizerIntent.LANGUAGE_MODEL_FREE_FORM)
        putExtra(RecognizerIntent.EXTRA_LANGUAGE, locale)
        putExtra(RecognizerIntent.EXTRA_PARTIAL_RESULTS, true)
        putExtra(RecognizerIntent.EXTRA_MAX_RESULTS, MAX_ALTERNATES)
        putExtra(
            RecognizerIntent.EXTRA_SPEECH_INPUT_COMPLETE_SILENCE_LENGTH_MILLIS,
            pauseMillis,
        )

        if (phrases.isNotEmpty()) {
            putStringArrayListExtra(
                EXTRA_SPEECH_INPUT_PHRASES,
                ArrayList(phrases),
            )
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            // Auto-casing and punctuation are the bulk of what makes dictation
            // read like typed text rather than a bare transcript.
            putExtra(EXTRA_ENABLE_FORMATTING, true)
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
            // Without this the engine may silently switch away from Bangla when
            // it thinks it hears another language.
            putExtra(EXTRA_ENABLE_LANGUAGE_DETECTION, false)
        }
    }

    private val listener = object : RecognitionListener {
        override fun onReadyForSpeech(params: Bundle?) = Unit
        override fun onBeginningOfSpeech() = Unit
        override fun onRmsChanged(rmsdB: Float) = Unit
        override fun onBufferReceived(buffer: ByteArray?) = Unit
        override fun onEndOfSpeech() = Unit
        override fun onEvent(eventType: Int, params: Bundle?) = Unit

        override fun onPartialResults(partialResults: Bundle?) {
            val partial = readBest(partialResults).first
            if (partial.isNotEmpty()) {
                emitResult(isFinal = false, partialOverride = partial)
            }
        }

        override fun onResults(results: Bundle?) {
            busy = false
            val (best, confidence) = readBest(results)
            if (best.isNotEmpty()) {
                emptyRestarts = 0
                appendTranscript(best)
                emitResult(isFinal = false)
            } else {
                emptyRestarts++
            }
            maybeRestart()
        }

        override fun onError(error: Int) {
            busy = false
            when (error) {
                SpeechRecognizer.ERROR_NO_MATCH,
                SpeechRecognizer.ERROR_SPEECH_TIMEOUT,
                SpeechRecognizer.ERROR_RECOGNIZER_BUSY,
                -> {
                    emptyRestarts++
                    maybeRestart()
                }

                else -> {
                    if (stopRequested) {
                        endSession(emitFinal = true)
                    } else {
                        endSession(emitFinal = true, errorCode = error)
                    }
                }
            }
        }
    }

    /** Returns the highest-confidence candidate and its score, if provided. */
    private fun readBest(results: Bundle?): Pair<String, Double> {
        val list = results?.getStringArrayList(SpeechRecognizer.RESULTS_RECOGNITION)
        if (list.isNullOrEmpty()) return "" to -1.0
        val scores = try {
            results.getFloatArray(SpeechRecognizer.CONFIDENCE_SCORES)
        } catch (e: Exception) {
            null
        }

        var bestIndex = 0
        var bestScore = scores?.firstOrNull()?.toDouble() ?: -1.0
        for (i in list.indices) {
            val score = scores?.getOrNull(i)?.toDouble() ?: -1.0
            if (score > bestScore) {
                bestScore = score
                bestIndex = i
            }
        }
        val text = list.getOrNull(bestIndex).orEmpty().trim()
        return text to (if (bestScore in 0.0..1.0) bestScore else -1.0)
    }

    private fun appendTranscript(text: String) {
        if (text.isEmpty()) return
        if (transcript.isNotEmpty() && !transcript.endsWith(" ")) {
            transcript.append(" ")
        }
        transcript.append(text)
    }

    private fun maybeRestart() {
        if (!sessionActive || stopRequested) {
            endSession(emitFinal = true)
            return
        }
        val elapsed = System.currentTimeMillis() - startedAt
        if (elapsed >= maxMillis || emptyRestarts > MAX_EMPTY_RESTARTS) {
            endSession(emitFinal = true)
            return
        }
        handler.postDelayed({ startListening(null) }, RESTART_DELAY_MS)
    }

    private fun endSession(emitFinal: Boolean, errorCode: Int? = null) {
        val wasActive = sessionActive
        sessionActive = false
        busy = false
        handler.removeCallbacksAndMessages(null)
        try {
            speechRecognizer?.destroy()
        } catch (e: Exception) {
            // Nothing actionable; the recognizer is being discarded anyway.
        }
        speechRecognizer = null

        // Emit before clearing, otherwise the final result would be blank.
        if (wasActive) {
            if (emitFinal) emitResult(isFinal = true)
            emitStatus("done")
        }
        transcript.setLength(0)
        emptyRestarts = 0

        if (errorCode != null) {
            channel?.invokeMethod(
                "voiceError",
                mapOf("code" to errorCode, "permanent" to true),
            )
        }
    }

    private fun emitResult(isFinal: Boolean, partialOverride: String? = null) {
        val text = partialOverride?.let { p ->
            if (transcript.isEmpty()) p else "${transcript.toString().trim()} $p"
        } ?: transcript.toString().trim()
        if (text.isEmpty() && !isFinal) return

        channel?.invokeMethod(
            "voiceResult",
            mapOf(
                "text" to text,
                "isFinal" to isFinal,
            ),
        )
    }

    private fun emitStatus(status: String) {
        channel?.invokeMethod("voiceStatus", mapOf("status" to status))
    }
}
