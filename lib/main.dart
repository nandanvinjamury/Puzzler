import 'package:flutter/material.dart';
import 'captcha.dart';
import 'progress.dart';
import 'puzzle_source.dart';
import 'screens/home_screen.dart';
import 'theme.dart';

/// Optional Lichess token (scope: puzzle:read). Not needed for the daily/next
/// puzzle endpoints, but kept for authenticated endpoints later.
// ignore: unused_element
const lichessToken = String.fromEnvironment('LICHESS_TOKEN');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = await ProgressStore.load();
  final cache = await PuzzleCache.load();
  // If Sleep as Android launched us as a captcha, we surface it on the home
  // screen (the sleeper taps Begin to solve the daily + 3 and dismiss).
  final captcha = await CaptchaBridge.instance.initialLaunch();
  runApp(PuzzlerApp(store: store, cache: cache, initialCaptcha: captcha));
}

class PuzzlerApp extends StatefulWidget {
  const PuzzlerApp({
    super.key,
    required this.store,
    required this.cache,
    this.initialCaptcha,
  });
  final ProgressStore store;
  final PuzzleCache cache;
  final CaptchaLaunch? initialCaptcha;

  @override
  State<PuzzlerApp> createState() => _PuzzlerAppState();
}

class _PuzzlerAppState extends State<PuzzlerApp> {
  final _navKey = GlobalKey<NavigatorState>();

  // Non-null while Sleep as Android is waiting on us: the home screen then runs
  // the daily-puzzle-plus-3 flow through Begin and dismisses on completion,
  // instead of jumping straight into solving.
  CaptchaLaunch? _captcha;

  @override
  void initState() {
    super.initState();
    // Warm launches (Sleep re-using our singleTop activity) come through here.
    CaptchaBridge.instance.onLaunch = _enterCaptcha;
    if (widget.initialCaptcha != null) {
      _captcha = widget.initialCaptcha;
      // Keep Sleep's captcha alive from the moment we land — before the sleeper
      // taps Begin — so it doesn't time out while the home screen is up.
      if (!widget.initialCaptcha!.isPreview) {
        WidgetsBinding.instance.addPostFrameCallback(
            (_) => CaptchaBridge.instance.startHeartbeat());
      }
    }
  }

  void _enterCaptcha(CaptchaLaunch launch) {
    setState(() => _captcha = launch);
    if (!launch.isPreview) CaptchaBridge.instance.startHeartbeat();
    // Make sure the sleeper is on the home screen, not some pushed route.
    _navKey.currentState?.popUntil((r) => r.isFirst);
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Puzzler',
        debugShowCheckedModeBanner: false,
        navigatorKey: _navKey,
        theme: buildDarkTheme(),
        home: HomeScreen(
          store: widget.store,
          cache: widget.cache,
          captcha: _captcha,
        ),
      );
}
