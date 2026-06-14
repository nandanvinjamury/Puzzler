import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'theme.dart';
import 'progress.dart';

/// The ten hues a daily streak cycles through over a year. The flame advances
/// gradually from one to the next and, after [_streakCycle.last] (gold), wraps
/// back to the first (yellow).
const List<Color> _streakCycle = [
  Color(0xFFFFD60A), // yellow
  Color(0xFFFF8C1A), // orange
  Color(0xFFFF3B30), // red
  Color(0xFFFF2D9B), // magenta
  Color(0xFF9B40FF), // purple
  Color(0xFF2F7BFF), // blue
  Color(0xFF34C759), // green
  Color(0xFFF2F2F2), // white
  Color(0xFFB9C2CC), // silver
  Color(0xFFE8B923), // gold
];

/// Calendar days to traverse the whole [_streakCycle] exactly once.
const double _streakCycleDays = 365.0;

/// Flame colours for a given daily [streak]: the outer hue advances gradually
/// through [_streakCycle] over a year (then wraps), and the inner flame is a
/// lighter tint of the same hue. A dead streak (0) shows a cold grey ember.
({Color outer, Color inner, Color glow}) flameColors(int streak) {
  if (streak <= 0) {
    return (
      outer: const Color(0xFF6B6864),
      inner: const Color(0xFF8E8982),
      glow: const Color(0xFF6B6864),
    );
  }
  final perColor = _streakCycleDays / _streakCycle.length; // ~36.5 days each
  final f = (streak - 1) / perColor; // continuous position along the cycle
  final i = f.floor();
  final a = _streakCycle[i % _streakCycle.length];
  final b = _streakCycle[(i + 1) % _streakCycle.length];
  final outer = Color.lerp(a, b, f - i)!;
  return (
    outer: outer,
    inner: Color.lerp(outer, Colors.white, 0.5)!,
    glow: outer,
  );
}

/// A hand-drawn flame whose color reflects [streak]. Static by default; pass
/// [animate] true (the center streak celebration) for gentle flickering.
class AnimatedFlame extends StatefulWidget {
  const AnimatedFlame({
    super.key,
    required this.size,
    required this.streak,
    this.animate = false,
  });
  final double size;
  final int streak;
  final bool animate;

  @override
  State<AnimatedFlame> createState() => _AnimatedFlameState();
}

class _AnimatedFlameState extends State<AnimatedFlame>
    with SingleTickerProviderStateMixin {
  // Created lazily only when the flame actually animates: a static flame (every
  // FireBadge) never spins up a ticker, and dispose never resurrects one.
  AnimationController? _c;

  AnimationController _controller() => _c ??= AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 850),
      );

  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller().repeat();
  }

  @override
  void didUpdateWidget(AnimatedFlame old) {
    super.didUpdateWidget(old);
    if (widget.animate) {
      final c = _controller();
      if (!c.isAnimating) c.repeat();
    } else {
      _c?.stop();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = flameColors(widget.streak);
    _FlamePainter painter(double t) => _FlamePainter(
          t: t,
          animated: widget.animate,
          outer: pal.outer,
          inner: pal.inner,
        );
    final size = Size(widget.size * 0.8, widget.size);
    if (!widget.animate) {
      return CustomPaint(size: size, painter: painter(0));
    }
    final c = _controller();
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) => CustomPaint(size: size, painter: painter(c.value)),
    );
  }
}

class _FlamePainter extends CustomPainter {
  _FlamePainter({
    required this.t,
    required this.animated,
    required this.outer,
    required this.inner,
  });

  final double t;
  final bool animated;
  final Color outer, inner;

  /// Bulb radius as a fraction of the canvas width.
  static const double _bulbFraction = 0.42;

  /// One plain sine oscillation in [-1, 1]; zero when static. Every stacked
  /// flame shares this single value, so they all sway at the same cadence.
  double get _sine => animated ? math.sin(t * 2 * math.pi) : 0.0;

  /// A flame silhouette: a circular bulb at the bottom that tapers to a sharp
  /// point at the top. [lean] slides the tip sideways (the sine sway) while the
  /// round base stays anchored.
  Path _flame(Size s, double lean) {
    final w = s.width, h = s.height;
    final cx = w / 2;
    final r = w * _bulbFraction; // bulb radius
    final cy = h - r; // bulb centre, a radius up from the base
    final tipX = cx + lean;
    final tipY = h * 0.04;
    final k = 0.5523 * r; // circle → cubic-bezier handle length

    return Path()
      // left shoulder (the bulb's equator, the flame's widest point)
      ..moveTo(cx - r, cy)
      // lower-left quarter of the bulb, down to the bottom
      ..cubicTo(cx - r, cy + k, cx - k, cy + r, cx, cy + r)
      // lower-right quarter, back up to the right shoulder
      ..cubicTo(cx + k, cy + r, cx + r, cy + k, cx + r, cy)
      // right flank sweeping up to the point
      ..cubicTo(cx + r, cy - r * 0.9, tipX + r * 0.28, tipY + h * 0.18, tipX, tipY)
      // left flank back down to the left shoulder
      ..cubicTo(tipX - r * 0.28, tipY + h * 0.18, cx - r, cy - r * 0.9, cx - r, cy)
      ..close();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final lean = _sine * size.width * 0.12;
    final path = _flame(size, lean);
    canvas.drawPath(path, Paint()..color = outer..isAntiAlias = true);

    // The exact same silhouette, scaled down and lighter, nested inside —
    // concentric with the bulb so it reads as a flame within the flame.
    final cx = size.width / 2;
    final cy = size.height - size.width * _bulbFraction;
    canvas
      ..save()
      ..translate(cx, cy)
      ..scale(0.58)
      ..translate(-cx, -cy)
      ..drawPath(path, Paint()..color = inner..isAntiAlias = true)
      ..restore();
  }

  @override
  bool shouldRepaint(_FlamePainter old) =>
      old.t != t ||
      old.animated != animated ||
      old.outer != outer ||
      old.inner != inner;
}

/// A bold lightning bolt that fills the exact same box as [AnimatedFlame]
/// (`size * 0.8` wide × `size` tall), so the flame and bolt streak badges line
/// up identically instead of the Material glyph's narrow, off-centre footprint.
class LightningBolt extends StatelessWidget {
  const LightningBolt({super.key, required this.size, this.color = AppColors.gold});
  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size(size * 0.8, size), painter: _BoltPainter(color));
}

class _BoltPainter extends CustomPainter {
  _BoltPainter(this.color);
  final Color color;

  // Bolt outline as fractions of the box, spanning ~the flame's footprint.
  static const _pts = <List<double>>[
    [0.60, 0.00],
    [0.12, 0.52],
    [0.46, 0.52],
    [0.32, 1.00],
    [0.90, 0.46],
    [0.54, 0.46],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final path = Path()..moveTo(_pts[0][0] * w, _pts[0][1] * h);
    for (var i = 1; i < _pts.length; i++) {
      path.lineTo(_pts[i][0] * w, _pts[i][1] * h);
    }
    path.close();
    canvas.drawPath(path, Paint()..color = color..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_BoltPainter old) => old.color != color;
}

/// A streak icon + count that pops when the count increments. One widget for
/// both streak cards (flame and bolt) so their sizing and spacing match exactly.
class StreakBadge extends StatefulWidget {
  const StreakBadge({
    super.key,
    required this.icon,
    required this.count,
    required this.active,
    this.size = 34,
  });

  /// The streak icon — an [AnimatedFlame] or a [LightningBolt] of [size].
  final Widget icon;
  final int count;
  final bool active;
  final double size;

  @override
  State<StreakBadge> createState() => _StreakBadgeState();
}

class _StreakBadgeState extends State<StreakBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pop = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 650),
  );

  @override
  void didUpdateWidget(StreakBadge old) {
    super.didUpdateWidget(old);
    if (widget.count > old.count) _pop.forward(from: 0);
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
        // A brief bump that returns to 1.0 (elasticOut settles at 1.0, which
        // left the icon permanently enlarged).
        final scale = 1 + 0.25 * math.sin(_pop.value * math.pi);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(scale: scale, child: widget.icon),
            const SizedBox(width: 8),
            Text(
              '${widget.count}',
              style: TextStyle(
                fontSize: widget.size * 0.78,
                fontWeight: FontWeight.w800,
                color: widget.active ? AppColors.text : AppColors.textMuted,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Full-screen fire burst shown when the daily streak increments.
Future<void> showStreakCelebration(BuildContext context, int streak) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'streak',
    barrierColor: Colors.black.withValues(alpha: 0.74),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => _StreakCelebration(streak: streak),
  );
}

class _StreakCelebration extends StatefulWidget {
  const _StreakCelebration({required this.streak});
  final int streak;

  @override
  State<_StreakCelebration> createState() => _StreakCelebrationState();
}

class _StreakCelebrationState extends State<_StreakCelebration>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1700),
  )..forward();

  final _sparks = List.generate(
    14,
    (i) => (
      angle: (i / 14) * 2 * math.pi,
      dist: 70.0 + (i % 4) * 26.0,
      size: 5.0 + (i % 3) * 3.0,
    ),
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pal = flameColors(widget.streak);
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final pop = Curves.elasticOut.transform(_c.value.clamp(0.0, 1.0));
              final spark = Curves.easeOut.transform(_c.value.clamp(0.0, 1.0));
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 260,
                    height: 260,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          width: 200,
                          height: 200,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: RadialGradient(colors: [
                              pal.glow.withValues(alpha: 0.45 * pop),
                              Colors.transparent,
                            ]),
                          ),
                        ),
                        for (final s in _sparks)
                          Transform.translate(
                            offset: Offset(
                              math.cos(s.angle) * s.dist * spark,
                              math.sin(s.angle) * s.dist * spark,
                            ),
                            child: Opacity(
                              opacity: (1 - spark).clamp(0.0, 1.0),
                              child: Container(
                                width: s.size,
                                height: s.size,
                                decoration: BoxDecoration(
                                  color: pal.inner,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                          ),
                        Transform.scale(
                          scale: 0.4 + 0.9 * pop,
                          child: AnimatedFlame(
                              size: 150, streak: widget.streak, animate: true),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${widget.streak} day streak!',
                    style: const TextStyle(
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                      color: AppColors.text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Keep the fire going',
                    style: TextStyle(color: AppColors.textMuted, fontSize: 15),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Level badge + animated XP progress bar.
class LevelXpBar extends StatelessWidget {
  const LevelXpBar({super.key, required this.store});
  final ProgressStore store;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: AppColors.green,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.green.withValues(alpha: 0.45),
                    blurRadius: 12,
                  ),
                ],
              ),
              alignment: Alignment.center,
              child: Text(
                '${store.level}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Level',
                          style: TextStyle(
                              color: AppColors.textMuted,
                              fontWeight: FontWeight.w600)),
                      Text('${store.xpIntoLevel} / ${store.xpForCurrentLevel} XP',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: TweenAnimationBuilder<double>(
                      tween: Tween(end: store.levelProgress.clamp(0.0, 1.0)),
                      duration: const Duration(milliseconds: 500),
                      curve: Curves.easeOut,
                      builder: (context, value, _) => LinearProgressIndicator(
                        value: value,
                        minHeight: 12,
                        backgroundColor: AppColors.bg,
                        valueColor:
                            const AlwaysStoppedAnimation(AppColors.green),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Brief "Level up!" burst.
Future<void> showLevelUp(BuildContext context, int level) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'levelup',
    barrierColor: Colors.black.withValues(alpha: 0.7),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (_, __, ___) => _LevelUp(level: level),
  );
}

class _LevelUp extends StatefulWidget {
  const _LevelUp({required this.level});
  final int level;

  @override
  State<_LevelUp> createState() => _LevelUpState();
}

class _LevelUpState extends State<_LevelUp>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..forward();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Center(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) {
              final pop = Curves.elasticOut.transform(_c.value.clamp(0.0, 1.0));
              return Transform.scale(
                scale: 0.5 + 0.5 * pop,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.military_tech,
                        size: 110,
                        color: AppColors.gold,
                        shadows: [
                          Shadow(
                              color: AppColors.gold.withValues(alpha: 0.6 * pop),
                              blurRadius: 30),
                        ]),
                    const SizedBox(height: 6),
                    const Text('LEVEL UP!',
                        style: TextStyle(
                            fontSize: 28,
                            fontWeight: FontWeight.w800,
                            color: AppColors.text,
                            letterSpacing: 1.5)),
                    Text('Level ${widget.level}',
                        style: const TextStyle(
                            fontSize: 18, color: AppColors.gold)),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
