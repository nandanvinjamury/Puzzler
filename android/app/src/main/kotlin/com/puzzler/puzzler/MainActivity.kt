package com.puzzler.puzzler

/**
 * The normal launcher entry point. It extends [CaptchaHostActivity] only so the
 * captcha method channel is available in every engine; its intent is never a
 * captcha launch, so it always reports `isCaptcha = false`. Sleep launches the
 * dedicated [CaptchaActivity] instead (that's what carries the OPEN filter).
 */
class MainActivity : CaptchaHostActivity()
