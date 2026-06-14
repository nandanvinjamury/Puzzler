import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../captcha.dart';
import '../lichess.dart';
import '../progress.dart';
import '../puzzle_board.dart';
import '../puzzle_source.dart';
import '../theme.dart';
import '../widgets.dart';
import 'puzzle_review_screen.dart';

const _wakeMessages = [
  'Wake up, Nandan! ♟',
  'Rise and grind, Nandan.',
  "Up and at 'em, Nandan.",
  'Morning, Nandan — find the win.',
  'No castling out of this one.',
  'Eyes open, Nandan. Spot the fork.',
];

class AlarmSessionScreen extends StatefulWidget {
  const AlarmSessionScreen({
    super.key,
    required this.store,
    required this.cache,
    this.captcha,
  });
  final ProgressStore store;
  final PuzzleCache cache;

  /// When non-null, this session is dismissing a Sleep as Android alarm: it runs
  /// [CaptchaLaunch.puzzleCount] random puzzles and signals Sleep on completion.
  final CaptchaLaunch? captcha;

  @override
  State<AlarmSessionScreen> createState() => _AlarmSessionScreenState();
}

class _AlarmSessionScreenState extends State<AlarmSessionScreen> {
  Puzzle? _current;
  int _stageIndex = 0;
  bool _loading = true;
  bool _currentSolved = false;
  bool _busy = false;
  String? _error;
  final Set<String> _seen = {};
  final List<Puzzle> _completed = []; // solved puzzles for past stages

  int _sessionXp = 0;
  bool _finished = false;
  String _caption = '';
  late final String _wake =
      _wakeMessages[Random().nextInt(_wakeMessages.length)];

  // ---- Session shape (differs for a Sleep captcha vs. the in-app alarm) ------

  bool get _isCaptcha => widget.captcha != null;
  bool get _isPreview => widget.captcha?.isPreview ?? false;
  // Same shape whether it's the in-app alarm or a Sleep captcha: the daily
  // puzzle + three randoms. (Sleep's 1–5 difficulty slider is intentionally
  // ignored — the sleeper always solves the daily plus three.)
  int get _randomCount => 3;
  bool get _includeDaily => true;
  int get _totalStages => (_includeDaily ? 1 : 0) + _randomCount;
  bool get _isDaily => _includeDaily && _stageIndex == 0;

  /// 1-based position of the current random puzzle (the daily, if any, is 0).
  int _randomOrdinal(int stage) => _includeDaily ? stage : stage + 1;

  String _stageLabel(int i) => _includeDaily && i == 0
      ? 'Daily'
      : 'Puzzle ${_randomOrdinal(i)} of $_randomCount';

  @override
  void initState() {
    super.initState();
    // The heartbeat normally started when Sleep dropped us on the home screen;
    // ensure it's running now that we're solving (startHeartbeat is idempotent).
    if (_isCaptcha && !_isPreview) CaptchaBridge.instance.startHeartbeat();
    _loadStage(0);
  }

  Future<void> _loadStage(int i) async {
    final isDailyStage = _includeDaily && i == 0;
    setState(() {
      _stageIndex = i;
      _loading = true;
      _currentSolved = false;
      _error = null;
      _current = null;
    });
    try {
      final p = isDailyStage
          ? await acquireDailyPuzzle(exclude: _seen)
          : await acquireRandomPuzzle(widget.cache, exclude: _seen);
      if (!mounted) return;
      _seen.add(p.id);
      setState(() {
        _current = p;
        _loading = false;
        _caption = isDailyStage
            ? 'Solve the daily puzzle to begin.'
            : 'Puzzle ${_randomOrdinal(i)} of $_randomCount';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  void _onMistake() {
    if (!_isDaily) widget.store.registerPuzzleMistake();
    setState(() => _caption = 'Not quite — try again.');
  }

  Future<void> _onSolved(bool clean) async {
    if (_busy || _currentSolved) return;
    _busy = true;
    if (_isCaptcha) CaptchaBridge.instance.alive();

    if (_isDaily) {
      final incremented = widget.store.recordActiveDay();
      setState(() => _caption = 'Daily solved!');
      if (incremented && mounted) {
        await showStreakCelebration(context, widget.store.dailyStreak);
      }
    } else {
      // Random puzzle (today's streak was already recorded by the daily stage).
      if (clean) {
        final levelBefore = widget.store.level;
        final gained = widget.store.registerPuzzleSolvedClean();
        _sessionXp += gained;
        setState(() => _caption = '+$gained XP');
        if (widget.store.level > levelBefore && mounted) {
          await showLevelUp(context, widget.store.level);
        }
      } else {
        setState(() => _caption = 'Nice try... better luck next time!');
      }
    }

    if (!mounted) return;
    setState(() {
      _currentSolved = true; // review/analyze; advance via the Next button
      _busy = false;
    });
  }

  void _next() {
    if (_current != null) _completed.add(_current!);
    if (_stageIndex < _totalStages - 1) {
      _loadStage(_stageIndex + 1);
    } else {
      setState(() => _finished = true);
      widget.cache.refill(); // top the cache back up for next time
      // Preview: Sleep ignores this. Real captcha: dismisses the alarm (and
      // stops the heartbeat).
      if (_isCaptcha) CaptchaBridge.instance.solved();
    }
  }

  void _reviewPast(int stage) {
    if (stage >= _completed.length) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PuzzleReviewScreen(
          puzzle: _completed[stage], label: _stageLabel(stage)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _body()),
    );
  }

  Widget _body() {
    if (_finished) {
      return _SessionComplete(
          store: widget.store, xp: _sessionXp, isCaptcha: _isCaptcha);
    }

    return Column(
      children: [
        // Integrated back control (no app bar) + the short wake line.
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back),
                color: AppColors.textMuted,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
              const Icon(Icons.alarm, color: AppColors.green, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                    _isPreview ? 'Captcha preview — solve to try it' : _wake,
                    style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 16)),
              ),
            ],
          ),
        ),
        if (_error != null)
          Expanded(child: _errorView())
        else ...[
          Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: Column(
            children: [
              _ProgressDots(
                  current: _stageIndex,
                  total: _totalStages,
                  onTapPast: _reviewPast),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _isDaily
                        ? 'Daily puzzle'
                        : 'Puzzle ${_randomOrdinal(_stageIndex)} of $_randomCount',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  Row(
                    children: [
                      _LiveStreakChip(streak: widget.store.puzzleStreak),
                      const SizedBox(width: 18),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.green,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text('Lv ${widget.store.level}',
                            style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                color: Colors.white)),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        Expanded(
          child: (_loading || _current == null)
              ? const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading puzzle…',
                          style: TextStyle(color: AppColors.textMuted)),
                    ],
                  ),
                )
              : PuzzleBoard(
                  key: ValueKey(_current!.id),
                  puzzle: _current!,
                  onMistake: _onMistake,
                  onSolved: _onSolved,
                  onProgress: (s) => setState(() => _caption = s),
                  // Caption (+ advance button once solved) sits just above the
                  // move list, which stays at the very bottom.
                  footer: _footer(),
                ),
        ),
        ],
      ],
    );
  }

  Widget _errorView() => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.wifi_off, size: 40, color: AppColors.textMuted),
              const SizedBox(height: 12),
              Text('Could not load puzzle:\n$_error',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: () => _loadStage(_stageIndex),
                  child: const Text('Retry')),
            ],
          ),
        ),
      );

  Widget _footer() {
    final last = _stageIndex == _totalStages - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(_caption,
                style:
                    const TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          ),
          if (_currentSolved) ...[
            const SizedBox(width: 12),
            Tooltip(
              message: last ? 'Dismiss alarm' : 'Next puzzle',
              child: FilledButton(
                onPressed: _next,
                style: FilledButton.styleFrom(
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(14),
                  minimumSize: const Size(52, 52),
                ),
                child: Icon(last ? Icons.alarm_off : Icons.arrow_forward,
                    size: 24),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Bolt + count that pops when the puzzle streak increments, live on screen.
class _LiveStreakChip extends StatefulWidget {
  const _LiveStreakChip({required this.streak});
  final int streak;

  @override
  State<_LiveStreakChip> createState() => _LiveStreakChipState();
}

class _LiveStreakChipState extends State<_LiveStreakChip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 500),
  );

  @override
  void didUpdateWidget(_LiveStreakChip old) {
    super.didUpdateWidget(old);
    if (widget.streak > old.streak) _pop.forward(from: 0);
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, _) {
        // Brief bump that returns to 1.0 (don't leave it permanently enlarged).
        final scale = 1 + 0.4 * sin(_pop.value * pi);
        return Transform.scale(
          scale: scale,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.bolt, color: AppColors.gold, size: 20),
              // Trailing padding so the count never crowds the level badge,
              // even mid-pop when the chip scales up.
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text(' ${widget.streak}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, color: AppColors.text)),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _ProgressDots extends StatelessWidget {
  const _ProgressDots(
      {required this.current, required this.total, required this.onTapPast});
  final int current;
  final int total;
  final ValueChanged<int> onTapPast;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < total; i++)
          Expanded(
            child: GestureDetector(
              onTap: i < current ? () => onTapPast(i) : null,
              child: Container(
                margin: EdgeInsets.only(right: i == total - 1 ? 0 : 6),
                height: 8,
                decoration: BoxDecoration(
                  color: i < current
                      ? AppColors.green
                      : (i == current
                          ? AppColors.green.withValues(alpha: 0.5)
                          : AppColors.surfaceHigh),
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SessionComplete extends StatelessWidget {
  const _SessionComplete(
      {required this.store, required this.xp, required this.isCaptcha});
  final ProgressStore store;
  final int xp;
  final bool isCaptcha;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.alarm_off, size: 64, color: AppColors.green),
            const SizedBox(height: 12),
            const Text('Alarm dismissed!',
                style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900)),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    _StatRow(label: 'XP earned', value: '+$xp'),
                    const Divider(height: 20),
                    _StatRow(
                        label: 'Puzzle streak', value: '${store.puzzleStreak}'),
                    const Divider(height: 20),
                    _StatRow(
                        label: 'Daily streak', value: '${store.dailyStreak}'),
                    const Divider(height: 20),
                    _StatRow(label: 'Level', value: 'Lv ${store.level}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                // A captcha session lives in its own activity launched by Sleep;
                // closing it returns the sleeper to Sleep as Android.
                onPressed: () => isCaptcha
                    ? SystemNavigator.pop()
                    : Navigator.of(context).pop(),
                child: Text(isCaptcha ? 'Close' : 'Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(color: AppColors.textMuted)),
        Text(value,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
      ],
    );
  }
}
