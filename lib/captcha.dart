import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Details of a Sleep as Android CAPTCHA launch handed to us by the native side.
///
/// Sleep launches Puzzler as a "captcha" the sleeper must solve to dismiss an
/// alarm. [isPreview] is true when Sleep is only showing a preview (while the
/// user picks/configures the captcha) — solving then must NOT dismiss anything.
/// [difficulty] is Sleep's 1–5 slider; we record it but the captcha shape is
/// fixed (the daily puzzle + 3 randoms), so it doesn't change the puzzle count.
@immutable
class CaptchaLaunch {
  const CaptchaLaunch({required this.isPreview, required this.difficulty});

  final bool isPreview;
  final int difficulty;

  factory CaptchaLaunch.fromMap(Map<dynamic, dynamic> m) => CaptchaLaunch(
        isPreview: m['isPreview'] == true,
        difficulty: (m['difficulty'] as int?) ?? 1,
      );
}

/// Bridge to the native Sleep as Android captcha contract (see
/// `MainActivity.kt`). On Android the activity is registered to handle Sleep's
/// `…captcha.intent.action.OPEN` launch; this class reads that launch and signals
/// `solved` / `alive` / `unsolved` back to Sleep over a method channel.
///
/// On every other platform the channel simply isn't there, so all calls no-op.
class CaptchaBridge {
  CaptchaBridge._() {
    _channel.setMethodCallHandler(_onCall);
  }

  static final CaptchaBridge instance = CaptchaBridge._();

  static const _channel = MethodChannel('com.puzzler.puzzler/captcha');

  /// Invoked when a captcha launch arrives while the app is already running
  /// (Sleep re-using our singleTop activity).
  void Function(CaptchaLaunch launch)? onLaunch;

  /// Reads the launch intent the app was (cold-)started with. Returns the
  /// captcha details when Sleep launched us as a captcha, else null.
  Future<CaptchaLaunch?> initialLaunch() async {
    if (defaultTargetPlatform != TargetPlatform.android) return null;
    // The native handler is registered in configureFlutterEngine, just before
    // the Dart entrypoint runs — retry briefly in case main() wins the race.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        final m = await _channel.invokeMapMethod<String, dynamic>('getLaunchInfo');
        if (m == null || m['isCaptcha'] != true) return null;
        return CaptchaLaunch.fromMap(m);
      } on MissingPluginException {
        await Future<void>.delayed(const Duration(milliseconds: 60));
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Timer? _heartbeat;

  /// Start pinging [alive] now and every 5s so Sleep doesn't time the captcha
  /// out. Spans the whole captcha — the home screen while the sleeper hasn't
  /// tapped Begin yet, and the solve session after — until [solved]/[unsolved].
  /// Idempotent; no-op off Android.
  void startHeartbeat() {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    if (_heartbeat != null) return;
    alive();
    _heartbeat = Timer.periodic(const Duration(seconds: 5), (_) => alive());
  }

  void stopHeartbeat() {
    _heartbeat?.cancel();
    _heartbeat = null;
  }

  /// The sleeper solved the captcha — tell Sleep to dismiss its alarm.
  Future<void> solved() {
    stopHeartbeat();
    return _invoke('solved');
  }

  /// Heartbeat so Sleep doesn't time the captcha out while the user is still
  /// thinking. Call periodically and on interaction.
  Future<void> alive() => _invoke('alive');

  /// The sleeper abandoned the captcha — Sleep should keep ringing.
  Future<void> unsolved() {
    stopHeartbeat();
    return _invoke('unsolved');
  }

  Future<void> _invoke(String method) async {
    if (defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod<void>(method);
    } catch (_) {
      // Best effort — never let a signalling failure crash the solve flow.
    }
  }

  Future<dynamic> _onCall(MethodCall call) async {
    if (call.method == 'onCaptchaLaunched') {
      final args = call.arguments;
      if (args is Map) onLaunch?.call(CaptchaLaunch.fromMap(args));
    }
    return null;
  }
}
