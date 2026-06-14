import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'engine.dart';
import 'lichess.dart';
import 'theme.dart';

enum _Badge { none, correct, wrong }

/// Renders a [Puzzle] with solution gating plus lichess-style move navigation.
///
/// While solving: correct moves advance (opponent reply auto-plays) and flash a
/// green check; wrong moves snap back and flash a red X. Once solved (or in
/// [reviewMode]), the board becomes a free **analysis board** — you can step
/// through the moves and play your own alternatives from any position, with a
/// "Solution" control to restore the puzzle line.
class PuzzleBoard extends StatefulWidget {
  const PuzzleBoard({
    super.key,
    required this.puzzle,
    this.onSolved,
    this.onMistake,
    this.onProgress,
    this.reviewMode = false,
    this.footer,
  });

  final Puzzle puzzle;
  final void Function(bool clean)? onSolved;
  final VoidCallback? onMistake;
  final ValueChanged<String>? onProgress;

  /// Opens directly in analysis with the full solution pre-played (for review).
  final bool reviewMode;

  /// Optional caption/controls rendered just above the move list (so the moves
  /// stay at the very bottom and the status text sits right above them).
  final Widget? footer;

  @override
  State<PuzzleBoard> createState() => _PuzzleBoardState();
}

class _PuzzleBoardState extends State<PuzzleBoard>
    with SingleTickerProviderStateMixin {
  // History: _positions[k] is the position after k plies; _moves[k]/_sans[k]
  // is the move leading _positions[k] -> _positions[k+1].
  final List<Position> _positions = [];
  final List<Move> _moves = [];
  final List<String> _sans = [];

  // Snapshot of the puzzle's solution line, to restore after exploring.
  List<Position> _solPositions = [];
  List<Move> _solMoves = [];
  List<String> _solSans = [];

  late ChessboardController _controller;
  late Side _orientation;
  int _viewPly = 0;
  bool _solved = false;
  bool _awaitingReply = false;
  bool _hadMistake = false;

  late final AnimationController _badgeCtl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 850),
  );
  _Badge _badge = _Badge.none;

  final ScrollController _moveScroll = ScrollController();

  // A single green arrow = the engine's best move for whoever is to move,
  // shown only in analysis (never while solving — it'd give the answer away).
  // A background isolate streams progressively deeper results, so the arrow
  // sharpens the longer you look. Olive/yellow-green (chess.com aesthetic, not a
  // minty green) but kept bright enough to read on the green board's dark squares.
  static const Color _arrowColor = Color(0xE67CB342);
  late final EngineService _engine = EngineService(_onEngineUpdate);
  Set<Shape> _engineShapes = const {};
  bool _engineThinking = false;
  String _engineLabel = '';

  int get _livePly => _positions.length - 1;
  int get _solIndex => _moves.length;
  bool get _isLive => _viewPly == _livePly;
  bool get _analysis => _solved;

  @override
  void initState() {
    super.initState();
    _reset();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _refreshEngine();
    });
  }

  @override
  void didUpdateWidget(PuzzleBoard old) {
    super.didUpdateWidget(old);
    if (old.puzzle.id != widget.puzzle.id) {
      _controller.dispose();
      _reset();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshEngine();
      });
    }
  }

  void _reset() {
    _positions
      ..clear()
      ..add(widget.puzzle.initialPosition);
    _moves.clear();
    _sans.clear();
    _orientation = widget.puzzle.orientation;
    _viewPly = 0;
    _solved = false;
    _awaitingReply = false;
    _hadMistake = false;
    _badge = _Badge.none;
    _engineShapes = const {};
    _engineThinking = false;
    _engineLabel = '';
    _engine.stop();
    _controller = ChessboardController(game: _gameForView());

    if (widget.reviewMode) {
      for (final uci in widget.puzzle.solution) {
        final mv = Move.parse(uci);
        if (mv == null || !_positions.last.isLegal(mv)) break;
        _push(mv);
      }
      _solved = true;
      _snapshotSolution();
      _viewPly = 0;
      _controller.updatePosition(_gameForView(), animate: false);
    }
  }

  @override
  void dispose() {
    _engine.dispose();
    _badgeCtl.dispose();
    _moveScroll.dispose();
    _controller.dispose();
    super.dispose();
  }

  PlayerSide get _solverSide =>
      _orientation == Side.white ? PlayerSide.white : PlayerSide.black;

  GameData _gameForView() {
    final pos = _positions[_viewPly];
    final interactive = _analysis ? true : (_isLive && !_awaitingReply);
    final lastMove =
        _viewPly == 0 ? widget.puzzle.setupMove : _moves[_viewPly - 1];
    return GameData(
      fen: pos.fen,
      lastMove: lastMove,
      playerSide: !interactive
          ? PlayerSide.none
          : (_analysis ? PlayerSide.both : _solverSide),
      sideToMove: pos.turn,
      validMoves: interactive ? makeLegalMoves(pos) : const {},
      kingSquareInCheck: pos.isCheck ? pos.board.kingOf(pos.turn) : null,
    );
  }

  void _updateBoard({bool animate = true}) =>
      _controller.updatePosition(_gameForView(), animate: animate);

  void _flashBadge(_Badge kind) {
    setState(() => _badge = kind);
    _badgeCtl.forward(from: 0);
  }

  void _push(Move move) {
    final pos = _positions.last;
    final (next, san) = pos.makeSan(move);
    _positions.add(next);
    _moves.add(move);
    _sans.add(san);
    _viewPly = _livePly;
  }

  void _snapshotSolution() {
    _solPositions = List.of(_positions);
    _solMoves = List.of(_moves);
    _solSans = List.of(_sans);
  }

  // ---- Solving -------------------------------------------------------------

  bool _matchesSolution(Move move, String expectedUci) {
    final pos = _positions.last;
    final expected = Move.parse(expectedUci);
    if (expected == null) return false;
    if (!pos.isLegal(move) || !pos.isLegal(expected)) return false;
    return pos.play(move).fen == pos.play(expected).fen;
  }

  void _onUserMove(Move move, {bool? viaDragAndDrop}) {
    if (_analysis) {
      _explore(move);
      return;
    }
    if (!_isLive || _awaitingReply) return;

    if (!_matchesSolution(move, widget.puzzle.solution[_solIndex])) {
      if (!_hadMistake) {
        _hadMistake = true;
        widget.onMistake?.call();
      }
      widget.onProgress?.call('Not the move — try again.');
      _flashBadge(_Badge.wrong);
      _updateBoard(animate: false);
      return;
    }

    _push(Move.parse(widget.puzzle.solution[_solIndex])!);
    _flashBadge(_Badge.correct);

    if (_solIndex >= widget.puzzle.solution.length) {
      _finish();
      return;
    }

    _awaitingReply = true;
    widget.onProgress?.call('Correct — keep going.');
    _updateBoard();
    _scrollMovesToEnd();
    setState(() {});

    Future.delayed(const Duration(milliseconds: 350), () {
      if (!mounted || _solved) return;
      _push(Move.parse(widget.puzzle.solution[_solIndex])!);
      _awaitingReply = false;
      if (_solIndex >= widget.puzzle.solution.length) {
        _finish();
      } else {
        _updateBoard();
        _scrollMovesToEnd();
        setState(() {});
      }
    });
  }

  void _finish() {
    _solved = true;
    _snapshotSolution();
    _updateBoard();
    _scrollMovesToEnd();
    widget.onProgress?.call(_hadMistake ? 'Solved (with a slip).' : 'Solved!');
    setState(() {});
    _refreshEngine(); // analysis is now open — start hinting
    widget.onSolved?.call(!_hadMistake);
  }

  // ---- Analysis ------------------------------------------------------------

  void _explore(Move move) {
    final pos = _positions[_viewPly];
    if (!pos.isLegal(move)) {
      _updateBoard(animate: false);
      return;
    }
    // Truncate any forward history at the viewed ply, then play the new move.
    if (_viewPly < _livePly) {
      _positions.removeRange(_viewPly + 1, _positions.length);
      _moves.removeRange(_viewPly, _moves.length);
      _sans.removeRange(_viewPly, _sans.length);
    }
    _push(move);
    _updateBoard();
    _scrollMovesToEnd();
    setState(() {});
    _refreshEngine();
  }

  void _restoreSolution() {
    _positions
      ..clear()
      ..addAll(_solPositions);
    _moves
      ..clear()
      ..addAll(_solMoves);
    _sans
      ..clear()
      ..addAll(_solSans);
    _viewPly = _livePly;
    _updateBoard();
    setState(() {});
    _refreshEngine();
  }

  // ---- Engine hints --------------------------------------------------------

  /// (Re)starts the streaming engine for the currently viewed position (analysis
  /// only). The isolate keeps searching deeper and pushes updates to
  /// [_onEngineUpdate]; restarting cancels any in-flight search for an old
  /// position, so its updates are discarded.
  void _refreshEngine() {
    if (!mounted || !_analysis) return;
    setState(() {
      _engineShapes = const {};
      _engineThinking = true;
      _engineLabel = 'Analysing…';
    });
    _engine.analyze(_positions[_viewPly].fen);
  }

  void _onEngineUpdate(EngineUpdate u) {
    if (!mounted || !_analysis) return;
    setState(() {
      _engineShapes = _arrowFor(u.best);
      _engineThinking = !u.done;
      _engineLabel = _engineStatus(u);
    });
  }

  Set<Shape> _arrowFor(String? best) {
    final mv = best != null ? Move.parse(best) : null;
    if (mv is! NormalMove) return const {};
    return {Arrow(color: _arrowColor, orig: mv.from, dest: mv.to)};
  }

  /// Compact "depth N · +1.2" / "depth N · M3" status for the engine chip.
  String _engineStatus(EngineUpdate u) {
    if (u.best == null) return 'no moves'; // terminal position (mate/stalemate)
    if (u.mateIn != null) {
      final n = u.mateIn!.abs();
      return 'depth ${u.depth} · ${u.mateIn! >= 0 ? 'M' : '-M'}$n';
    }
    final pawns = u.scoreCp / 100.0;
    return 'depth ${u.depth} · ${pawns >= 0 ? '+' : ''}${pawns.toStringAsFixed(1)}';
  }

  // ---- Navigation ----------------------------------------------------------

  void _goTo(int ply) {
    final target = ply.clamp(0, _livePly);
    if (target == _viewPly) return;
    setState(() => _viewPly = target);
    _updateBoard();
    _refreshEngine();
  }

  void _scrollMovesToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_moveScroll.hasClients) {
        _moveScroll.animateTo(
          _moveScroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Reserve fixed space for the chip row, footer and move list; the rest
        // goes to the square board plus the flex gaps. The chip's height is
        // always reserved (stable board position), the top gap pushes the board
        // down off the header, and the bottom gap centres the caption above the
        // move list.
        const chipH = 32.0, navH = 56.0, footerH = 52.0;
        final boardSize = math
            .min(constraints.maxWidth,
                constraints.maxHeight - chipH - navH - footerH - 24)
            .clamp(160.0, 460.0);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Sit the chip in the middle of the top gap (a 1:1 split of the same
            // flex-2 region) so it's a little lower without moving the board.
            // Its height is always reserved so nothing shifts; the chip itself
            // only shows in analysis — before solving it has nothing to say.
            const Spacer(flex: 1),
            SizedBox(
              height: chipH,
              child: _analysis
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: _EngineChip(
                            thinking: _engineThinking, label: _engineLabel),
                      ),
                    )
                  : null,
            ),
            const Spacer(flex: 1),
            Center(
              child: SizedBox(
                width: boardSize,
                height: boardSize,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Chessboard(
                      controller: _controller,
                      size: boardSize,
                      orientation: _orientation,
                      settings: const ChessboardSettings(
                        colorScheme: chesscomBoard,
                        enableCoordinates: true,
                        animationDuration: Duration(milliseconds: 200),
                      ),
                      // Engine best-move arrow (analysis only).
                      shapes: _engineShapes,
                      onMove: _onUserMove,
                    ),
                    _MoveResultBadge(controller: _badgeCtl, badge: _badge),
                  ],
                ),
              ),
            ),
            // Caption (footer) vertically centred in the larger gap below the
            // board (≈2:5 split with the top gap) — evenly spaced, not crammed
            // against the move bar.
            Expanded(
              flex: 5,
              child: widget.footer == null
                  ? const SizedBox.shrink()
                  : Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [widget.footer!],
                    ),
            ),
            _MoveNavBar(
              sans: _sans,
              positions: _positions,
              viewPly: _viewPly,
              livePly: _livePly,
              scrollController: _moveScroll,
              onGoTo: _goTo,
              analysis: _analysis,
              onReset: _restoreSolution,
            ),
          ],
        );
      },
    );
  }
}

/// Pops a green check (correct) or red X (wrong) over the board, then fades.
class _MoveResultBadge extends StatelessWidget {
  const _MoveResultBadge({required this.controller, required this.badge});
  final AnimationController controller;
  final _Badge badge;

  @override
  Widget build(BuildContext context) {
    if (badge == _Badge.none) return const SizedBox.shrink();
    final correct = badge == _Badge.correct;
    final color = correct ? AppColors.green : const Color(0xFFE0524F);
    return IgnorePointer(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) {
          final v = controller.value;
          if (v == 0 || v >= 1) return const SizedBox.shrink();
          final scale =
              0.4 + 0.6 * Curves.elasticOut.transform(v.clamp(0.0, 1.0));
          final opacity = v < 0.7 ? 1.0 : (1 - (v - 0.7) / 0.3);
          return Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform.scale(
              scale: scale,
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                        color: color.withValues(alpha: 0.5), blurRadius: 24),
                  ],
                ),
                child: Icon(
                  correct ? Icons.check_rounded : Icons.close_rounded,
                  color: Colors.white,
                  size: 60,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Slim status pill above the board: a spinner while the engine keeps deepening,
/// then the depth + evaluation. The green arrow it draws is the best move for
/// whoever is to move.
class _EngineChip extends StatelessWidget {
  const _EngineChip({required this.thinking, required this.label});
  final bool thinking;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: thinking
                ? const CircularProgressIndicator(
                    strokeWidth: 2, color: AppColors.green)
                : const Icon(Icons.lightbulb, size: 12, color: AppColors.green),
          ),
          const SizedBox(width: 6),
          Text(
            label.isEmpty ? 'Engine' : 'Engine · $label',
            style: const TextStyle(
                color: AppColors.text,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// Back/forward controls + a horizontally scrollable, clickable SAN move list.
class _MoveNavBar extends StatelessWidget {
  const _MoveNavBar({
    required this.sans,
    required this.positions,
    required this.viewPly,
    required this.livePly,
    required this.scrollController,
    required this.onGoTo,
    required this.analysis,
    required this.onReset,
  });

  final List<String> sans;
  final List<Position> positions;
  final int viewPly;
  final int livePly;
  final ScrollController scrollController;
  final ValueChanged<int> onGoTo;
  final bool analysis;
  final VoidCallback onReset;

  @override
  Widget build(BuildContext context) {
    return Container(
      // Flat top edge, flush to the screen — no rounded corners.
      color: AppColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
      child: Row(
        children: [
          _navButton(Icons.first_page, viewPly > 0, () => onGoTo(0)),
          _navButton(
              Icons.chevron_left, viewPly > 0, () => onGoTo(viewPly - 1)),
          Expanded(
            child: SizedBox(
              height: 36,
              child: sans.isEmpty
                  ? Center(
                      child: Text(analysis ? 'Analysis' : 'Your move',
                          style: const TextStyle(
                              color: AppColors.textMuted, fontSize: 13)),
                    )
                  : ListView(
                      controller: scrollController,
                      scrollDirection: Axis.horizontal,
                      children: [
                        for (var i = 0; i < sans.length; i++) _moveToken(i),
                      ],
                    ),
            ),
          ),
          _navButton(Icons.chevron_right, viewPly < livePly,
              () => onGoTo(viewPly + 1)),
          _navButton(Icons.last_page, viewPly < livePly, () => onGoTo(livePly)),
          if (analysis)
            IconButton(
              visualDensity: VisualDensity.compact,
              tooltip: 'Back to solution',
              icon: const Icon(Icons.restore),
              color: AppColors.green,
              onPressed: onReset,
            ),
        ],
      ),
    );
  }

  Widget _moveToken(int i) {
    final before = positions[i];
    final isWhite = before.turn == Side.white;
    final number = before.fullmoves;
    final label = isWhite
        ? '$number. ${sans[i]}'
        : (i == 0 ? '$number… ${sans[i]}' : sans[i]);
    final selected = viewPly == i + 1;
    return GestureDetector(
      onTap: () => onGoTo(i + 1),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 2),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? AppColors.green : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            color: selected ? Colors.white : AppColors.text,
            fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
            fontSize: 14,
          ),
        ),
      ),
    );
  }

  Widget _navButton(IconData icon, bool enabled, VoidCallback onTap) {
    return IconButton(
      visualDensity: VisualDensity.compact,
      icon: Icon(icon),
      color: AppColors.text,
      disabledColor: AppColors.textMuted.withValues(alpha: 0.4),
      onPressed: enabled ? onTap : null,
    );
  }
}
