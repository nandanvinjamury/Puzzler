package com.puzzler.puzzler

import android.content.Intent
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Base Flutter activity that implements the Sleep as Android captcha contract
 * (package `com.urbandroid.sleep.captcha`).
 *
 * Sleep launches the dedicated [CaptchaActivity] with [ACTION_LAUNCH] when the
 * sleeper must solve a captcha to dismiss an alarm. The launch intent carries
 * pre-built callback [Intent]s as parcelable extras keyed by event name
 * ("solved"/"unsolved"/"alive"); to report an event we fire the matching
 * callback intent the way the official support library does. Everything is
 * bridged to Dart over a [MethodChannel] so the existing puzzle UI can drive it.
 *
 * The plain launcher [MainActivity] extends this too; its intent is never a
 * captcha launch, so `getLaunchInfo` simply reports `isCaptcha = false` (and the
 * channel is present, so Dart never waits on a missing handler).
 */
open class CaptchaHostActivity : FlutterActivity() {
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "getLaunchInfo" -> result.success(launchInfo(intent))
                    "solved" -> { signal(EVENT_SOLVED); result.success(null) }
                    "unsolved" -> { signal(EVENT_UNSOLVED); result.success(null) }
                    "alive" -> { signal(EVENT_ALIVE); result.success(null) }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        // singleTop: a captcha launch while we're already running arrives here.
        setIntent(intent)
        if (isCaptcha(intent)) {
            channel?.invokeMethod("onCaptchaLaunched", launchInfo(intent))
        }
    }

    private fun isCaptcha(intent: Intent?): Boolean {
        val action = intent?.action ?: return false
        return action == ACTION_LAUNCH || action == ACTION_CONFIG
    }

    private fun isOperational(intent: Intent): Boolean {
        val preview = intent.getBooleanExtra(EXTRA_PREVIEW, false)
        val config = intent.action == ACTION_CONFIG
        return !preview && !config
    }

    private fun launchInfo(intent: Intent?): Map<String, Any> = mapOf(
        "isCaptcha" to isCaptcha(intent),
        "isPreview" to (intent?.getBooleanExtra(EXTRA_PREVIEW, false) ?: false),
        "difficulty" to (intent?.getIntExtra(EXTRA_DIFFICULTY, 1) ?: 1),
    )

    @Suppress("DEPRECATION")
    private fun callbackIntent(launch: Intent, event: String): Intent? =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            launch.getParcelableExtra(event, Intent::class.java)
        } else {
            launch.getParcelableExtra(event) as? Intent
        }

    /**
     * Fires the callback intent Sleep handed us for [event], mirroring the
     * support library's `BaseCaptchaSupport.send`: alive is always a broadcast;
     * solved/unsolved broadcast for in-place alarm operations but otherwise
     * start Sleep's captcha activity (the normal "dismiss the alarm" path).
     */
    private fun signal(event: String) {
        val launch = intent ?: return
        if (!isOperational(launch)) return
        val callback = callbackIntent(launch, event) ?: return
        val hasOperation = !launch.hasExtra(OPERATION_NONE)

        when (event) {
            EVENT_ALIVE -> {
                if (callback.`package` == null && callback.component == null) {
                    callback.setPackage(packageName)
                }
                callback.putExtra(EXTRA_TIME_ADD, ALIVE_TIMEOUT_SECONDS)
                sendBroadcast(callback)
            }
            EVENT_UNSOLVED -> {
                if (!hasOperation) {
                    callback.addFlags(
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP,
                    )
                    startActivity(callback)
                }
            }
            EVENT_SOLVED -> {
                val nested = launch.getIntExtra(EXTRA_PARENT_ID, 0) != 0
                if (hasOperation && !nested) {
                    sendBroadcast(callback)
                } else {
                    callback.addFlags(
                        Intent.FLAG_ACTIVITY_CLEAR_TOP or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP or
                            Intent.FLAG_INCLUDE_STOPPED_PACKAGES or
                            Intent.FLAG_ACTIVITY_NEW_TASK,
                    )
                    try {
                        startActivity(callback)
                    } catch (e: Exception) {
                        // Fall back to addressing Sleep's captcha pack explicitly.
                        try {
                            val copy = Intent(callback.action).apply {
                                addFlags(callback.flags)
                                setPackage(CAPTCHA_PACK)
                                callback.extras?.let { putExtras(it) }
                            }
                            startActivity(copy)
                        } catch (_: Exception) {
                            // Give up silently — the alarm will re-prompt.
                        }
                    }
                }
            }
        }
    }

    companion object {
        private const val CHANNEL = "com.puzzler.puzzler/captcha"

        // Sleep as Android captcha contract (com.urbandroid.sleep.captcha).
        private const val ACTION_LAUNCH = "com.urbandroid.sleep.captcha.intent.action.OPEN"
        private const val ACTION_CONFIG = "com.urbandroid.sleep.captcha.intent.action.CONFIG"
        private const val EXTRA_PREVIEW = "preview"
        private const val EXTRA_DIFFICULTY = "difficulty"
        private const val EXTRA_PARENT_ID = "captchaParentId"
        private const val EXTRA_TIME_ADD = "timeAddInSeconds"
        private const val OPERATION_NONE = "no_operation"
        private const val EVENT_SOLVED = "solved"
        private const val EVENT_UNSOLVED = "unsolved"
        private const val EVENT_ALIVE = "alive"
        private const val CAPTCHA_PACK = "com.urbandroid.sleep.captchapack"
        private const val ALIVE_TIMEOUT_SECONDS = 60
    }
}
