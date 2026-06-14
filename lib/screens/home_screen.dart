import 'package:flutter/material.dart';
import '../captcha.dart';
import '../progress.dart';
import '../puzzle_source.dart';
import '../theme.dart';
import '../widgets.dart';
import 'alarm_session_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen(
      {super.key, required this.store, required this.cache, this.captcha});
  final ProgressStore store;
  final PuzzleCache cache;

  /// Non-null when Sleep as Android launched us to dismiss an alarm. The Begin
  /// button then runs the solve flow as a captcha and signals Sleep when done.
  final CaptchaLaunch? captcha;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // Opportunistically top up the puzzle cache while the app is open.
    widget.cache.refill();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Puzzler',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 24)),
        actions: [
          IconButton(
            tooltip: 'Use with Sleep as Android',
            icon: const Icon(Icons.bedtime_outlined, color: AppColors.textMuted),
            onPressed: () => _showSleepHelp(context),
          ),
          IconButton(
            tooltip: 'Reset progress',
            icon: const Icon(Icons.restart_alt, color: AppColors.textMuted),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Reset progress?'),
                  content: const Text(
                      'Clears streaks, XP and level. This cannot be undone.'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('Reset')),
                  ],
                ),
              );
              if (ok == true) await widget.store.reset();
            },
          ),
        ],
      ),
      body: SafeArea(
        child: ListenableBuilder(
          listenable: widget.store,
          builder: (context, _) => SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: LevelXpBar(store: widget.store),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(child: _DailyStreakCard(store: widget.store)),
                    const SizedBox(width: 12),
                    Expanded(child: _PuzzleStreakCard(store: widget.store)),
                  ],
                ),
                const SizedBox(height: 20),
                _AlarmCard(
                    store: widget.store,
                    cache: widget.cache,
                    captcha: widget.captcha),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSleepHelp(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.bedtime, color: AppColors.green, size: 22),
            SizedBox(width: 8),
            Expanded(child: Text('Use with Sleep as Android')),
          ],
        ),
        content: const Text(
          'Dismiss your alarm by solving chess puzzles.\n\n'
          '1.  Install Sleep as Android.\n\n'
          '2.  Edit any alarm → CAPTCHA → pick “Chess puzzle”.\n\n'
          '3.  Difficulty sets how many puzzles you solve (1–5).\n\n'
          'Not listed? It’s called “Chess puzzle” (not “Puzzler”). If it’s '
          'still missing, force-stop Sleep as Android (its App info → Force '
          'stop) and reopen it so it re-scans — needs a recent version.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }
}

class _DailyStreakCard extends StatelessWidget {
  const _DailyStreakCard({required this.store});
  final ProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Daily streak',
                style: TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            StreakBadge(
              icon: AnimatedFlame(size: 34, streak: store.dailyStreak),
              count: store.dailyStreak,
              active: store.dailyStreak > 0,
            ),
            const SizedBox(height: 6),
            Text(
              store.dailyStreak == 0 ? 'Solve today to start' : 'days in a row',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}

class _PuzzleStreakCard extends StatelessWidget {
  const _PuzzleStreakCard({required this.store});
  final ProgressStore store;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Puzzle streak',
                style: TextStyle(
                    color: AppColors.textMuted, fontWeight: FontWeight.w600)),
            const SizedBox(height: 10),
            StreakBadge(
              icon: const LightningBolt(size: 34),
              count: store.puzzleStreak,
              active: store.puzzleStreak > 0,
            ),
            const SizedBox(height: 6),
            Text('best ${store.bestPuzzleStreak}',
                style:
                    const TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _AlarmCard extends StatelessWidget {
  const _AlarmCard({required this.store, required this.cache, this.captcha});
  final ProgressStore store;
  final PuzzleCache cache;
  final CaptchaLaunch? captcha;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: AppColors.surfaceHigh,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const Icon(Icons.alarm, size: 40, color: AppColors.green),
            const SizedBox(height: 10),
            const Text('Dismiss the alarm',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text('Solve the daily puzzle + 3 more to turn it off',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textMuted)),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                icon: const Icon(Icons.play_arrow),
                label: const Text('Begin'),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                      builder: (_) => AlarmSessionScreen(
                          store: store, cache: cache, captcha: captcha)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
