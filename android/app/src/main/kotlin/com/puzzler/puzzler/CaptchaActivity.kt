package com.puzzler.puzzler

/**
 * Dedicated Sleep as Android captcha activity. Sleep discovers and launches this
 * (via the `…captcha.intent.action.OPEN` filter in the manifest) when the
 * sleeper must solve a chess puzzle to dismiss an alarm. Kept separate from the
 * launcher [MainActivity] because Sleep lists a dedicated captcha activity (the
 * canonical pattern) rather than an app's main launcher activity.
 */
class CaptchaActivity : CaptchaHostActivity()
