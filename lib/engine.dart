import 'dart:isolate';
import 'dart:typed_data';
import 'package:dartchess/dartchess.dart';

/// A compact, fully-offline chess engine used to draw "best line" hint arrows on
/// the analysis board: negamax + alpha-beta + quiescence, **iterative deepening
/// that streams progressively deeper results over time**, with killer-move and
/// history ordering, check extensions and a tapered piece-square eval.
///
/// Two entry points:
/// * [EngineService] — drives a background isolate that keeps searching deeper
///   and streams an [EngineUpdate] after every completed depth (this is what the
///   UI uses; the arrows sharpen the longer you stay on a position).
/// * [engineLine] — a synchronous fixed-depth probe used by tests.

// ---- Public results ---------------------------------------------------------

/// One completed search iteration, streamed from the engine isolate.
class EngineUpdate {
  const EngineUpdate({
    required this.depth,
    required this.best,
    required this.reply,
    required this.scoreCp,
    required this.mateIn,
    required this.done,
  });

  /// Search depth (plies) this result was found at.
  final int depth;

  /// Best move for the side to move, UCI (e.g. "g1f3", "e7e8q"), or null.
  final String? best;

  /// The opponent's best reply (PV ply 2), UCI, or null.
  final String? reply;

  /// Evaluation in centipawns from the side-to-move's perspective.
  final int scoreCp;

  /// Mate distance in moves (positive = side to move mates, negative = gets
  /// mated), or null if no forced mate is seen.
  final int? mateIn;

  /// True once the engine has stopped deepening (depth cap, time, or mate).
  final bool done;
}

/// Fixed-depth probe (synchronous). Returns the principal variation's first two
/// plies. Used by tests; the app uses [EngineService].
EngineUpdate engineLine(String fen, {int maxDepth = 6}) {
  try {
    final pos = Chess.fromSetup(Setup.parseFen(fen));
    EngineUpdate? last;
    _searchDeepening(pos, maxDepth: maxDepth, timeMs: 1 << 30, emit: (u) => last = u);
    return last ??
        const EngineUpdate(
            depth: 0, best: null, reply: null, scoreCp: 0, mateIn: null, done: true);
  } catch (_) {
    return const EngineUpdate(
        depth: 0, best: null, reply: null, scoreCp: 0, mateIn: null, done: true);
  }
}

// ---- Background service -----------------------------------------------------

class _EngineRequest {
  _EngineRequest(this.sendPort, this.fen, this.maxDepth, this.timeMs);
  final SendPort sendPort;
  final String fen;
  final int maxDepth;
  final int timeMs;
}

/// Manages a single search isolate, restarting it whenever the analysed
/// position changes. Updates from a superseded position are dropped.
class EngineService {
  EngineService(this.onUpdate);

  final void Function(EngineUpdate update) onUpdate;

  Isolate? _isolate;
  ReceivePort? _port;
  int _gen = 0;

  /// Start (or restart) analysis of [fen]. Cancels any in-flight search.
  Future<void> analyze(String fen, {int maxDepth = 64, int timeMs = 10000}) async {
    final gen = ++_gen;
    _stop();
    final port = ReceivePort();
    _port = port;
    port.listen((msg) {
      if (gen != _gen) return; // superseded
      if (msg is EngineUpdate) onUpdate(msg);
    });
    try {
      final iso = await Isolate.spawn(
        _engineEntry,
        _EngineRequest(port.sendPort, fen, maxDepth, timeMs),
      );
      if (gen != _gen) {
        iso.kill(priority: Isolate.immediate); // a newer request already won
      } else {
        _isolate = iso;
      }
    } catch (_) {
      // spawn failed — leave arrows unchanged
    }
  }

  /// Stop the current search without starting a new one.
  void stop() {
    _gen++;
    _stop();
  }

  void _stop() {
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _port?.close();
    _port = null;
  }

  void dispose() => stop();
}

void _engineEntry(_EngineRequest req) {
  try {
    final pos = Chess.fromSetup(Setup.parseFen(req.fen));
    _searchDeepening(
      pos,
      maxDepth: req.maxDepth,
      timeMs: req.timeMs,
      emit: req.sendPort.send,
    );
  } catch (_) {
    // ignore — isolate just exits
  }
}

// ---- Search -----------------------------------------------------------------

const int _inf = 1 << 24;
const int _mate = 1 << 20;
const int _maxPly = 80;

/// Iterative deepening: search depth 1, 2, 3, … emitting the best line found at
/// each depth, until [maxDepth], the [timeMs] budget, or a forced mate.
void _searchDeepening(
  Position root, {
  required int maxDepth,
  required int timeMs,
  required void Function(EngineUpdate) emit,
}) {
  final s = _Search(timeMs);
  List<NormalMove> pv = const [];
  var lastScore = 0;

  for (var depth = 1; depth <= maxDepth && depth < _maxPly - 2; depth++) {
    final score = _searchRoot(root, depth, s, pv.isNotEmpty ? pv.first : null);
    if (s.aborted) break; // ran out of time mid-iteration; keep the last result

    pv = List.of(s.pv[0]);
    lastScore = score;
    if (pv.isEmpty) break; // no legal moves

    final mate = _mateInMoves(score);
    final timeUp = s.elapsedMs >= timeMs;
    emit(EngineUpdate(
      depth: depth,
      best: pv.isNotEmpty ? pv[0].uci : null,
      reply: pv.length > 1 ? pv[1].uci : null,
      scoreCp: score,
      mateIn: mate,
      done: depth >= maxDepth || mate != null || timeUp,
    ));
    if (mate != null || timeUp) return; // mate found or out of time
  }

  // Emit a terminal marker if the loop ended without a `done` update.
  emit(EngineUpdate(
    depth: pv.isEmpty ? 0 : maxDepth,
    best: pv.isNotEmpty ? pv[0].uci : null,
    reply: pv.length > 1 ? pv[1].uci : null,
    scoreCp: lastScore,
    mateIn: _mateInMoves(lastScore),
    done: true,
  ));
}

class _Search {
  _Search(this.deadlineMs);
  final int deadlineMs;
  final Stopwatch _sw = Stopwatch()..start();
  int nodes = 0;
  bool aborted = false;

  // Two killer moves per ply + a from/to history table for quiet-move ordering.
  final List<List<NormalMove?>> killers =
      List.generate(_maxPly, (_) => <NormalMove?>[null, null], growable: false);
  final Int32List history = Int32List(64 * 64);
  // Triangular principal-variation table: pv[ply] is the best line from ply.
  final List<List<NormalMove>> pv =
      List.generate(_maxPly, (_) => <NormalMove>[], growable: false);

  int get elapsedMs => _sw.elapsedMilliseconds;

  bool get timedOut {
    if ((nodes & 1023) == 0 && _sw.elapsedMilliseconds >= deadlineMs) {
      aborted = true;
    }
    return aborted;
  }
}

int _searchRoot(Position pos, int depth, _Search s, NormalMove? pvMove) {
  s.pv[0].clear();
  final moves = _legalMoves(pos);
  if (moves.isEmpty) return pos.isCheck ? -_mate : 0;
  _order(pos, moves, 0, s, pvMove);

  var alpha = -_inf;
  for (final m in moves) {
    final score = -_negamax(pos.play(m), depth - 1, -_inf, -alpha, 1, s);
    if (s.aborted) return alpha;
    if (score > alpha) {
      alpha = score;
      s.pv[0]
        ..clear()
        ..add(m)
        ..addAll(s.pv[1]);
    }
  }
  return alpha;
}

int _negamax(Position pos, int depth, int alpha, int beta, int ply, _Search s) {
  s.pv[ply].clear();
  if (ply >= _maxPly - 2) return _eval(pos);
  s.nodes++;
  if (s.timedOut) return alpha;

  final inCheck = pos.isCheck;
  if (inCheck) depth++; // check extension — chase tactics a ply further

  if (depth <= 0) return _quiesce(pos, alpha, beta, s);

  final moves = _legalMoves(pos);
  if (moves.isEmpty) return inCheck ? -(_mate - ply) : 0; // mate (by ply) or stalemate

  _order(pos, moves, ply, s, null);

  var best = -_inf;
  for (final m in moves) {
    final score = -_negamax(pos.play(m), depth - 1, -beta, -alpha, ply + 1, s);
    if (s.aborted) return best > -_inf ? best : alpha;
    if (score > best) best = score;
    if (score > alpha) {
      alpha = score;
      s.pv[ply]
        ..clear()
        ..add(m)
        ..addAll(s.pv[ply + 1]);
    }
    if (alpha >= beta) {
      // Quiet move that caused a cutoff → remember it for ordering.
      if (pos.board.pieceAt(m.to) == null && m.promotion == null) {
        final k = s.killers[ply];
        if (!_same(k[0], m)) {
          k[1] = k[0];
          k[0] = m;
        }
        s.history[(m.from << 6) | m.to] += depth * depth;
      }
      break;
    }
  }
  return best;
}

/// Captures-only search past the horizon so a last-ply hanging piece doesn't
/// fool the static eval — the difference between useful and useless tactics.
int _quiesce(Position pos, int alpha, int beta, _Search s) {
  s.nodes++;
  if (s.timedOut) return alpha;

  final standPat = _eval(pos);
  if (standPat >= beta) return beta;
  if (standPat > alpha) alpha = standPat;

  final captures = <NormalMove>[];
  for (final m in _legalMoves(pos)) {
    if (pos.board.pieceAt(m.to) != null) captures.add(m);
  }
  _order(pos, captures, -1, s, null);
  for (final m in captures) {
    final score = -_quiesce(pos.play(m), -beta, -alpha, s);
    if (s.aborted) return alpha;
    if (score >= beta) return beta;
    if (score > alpha) alpha = score;
  }
  return alpha;
}

// ---- Move generation & ordering ---------------------------------------------

List<NormalMove> _legalMoves(Position pos) {
  final moves = <NormalMove>[];
  pos.legalMoves.forEach((from, dests) {
    final isPawn = pos.board.pieceAt(from)?.role == Role.pawn;
    for (final to in dests.squares) {
      final rank = to >> 3;
      if (isPawn && (rank == 0 || rank == 7)) {
        moves.add(NormalMove(from: from, to: to, promotion: Role.queen));
        moves.add(NormalMove(from: from, to: to, promotion: Role.knight));
      } else {
        moves.add(NormalMove(from: from, to: to));
      }
    }
  });
  return moves;
}

/// Orders moves: PV move, then captures (MVV-LVA), promotions, killer moves,
/// then quiet moves by history score. [ply] == -1 means quiescence (no killers).
void _order(Position pos, List<NormalMove> moves, int ply, _Search s, NormalMove? pvMove) {
  final killers = ply >= 0 ? s.killers[ply] : const <NormalMove?>[null, null];
  int score(NormalMove m) {
    if (pvMove != null && _same(pvMove, m)) return 1 << 28;
    final victim = pos.board.pieceAt(m.to);
    if (victim != null) {
      final attacker = pos.board.pieceAt(m.from);
      return (1 << 26) +
          _value[victim.role]! * 16 -
          (attacker != null ? _value[attacker.role]! : 0);
    }
    if (m.promotion != null) return (1 << 25) + _value[m.promotion]!;
    if (_same(killers[0], m)) return (1 << 24) + 1;
    if (_same(killers[1], m)) return 1 << 24;
    return s.history[(m.from << 6) | m.to];
  }

  moves.sort((a, b) => score(b).compareTo(score(a)));
}

bool _same(NormalMove? a, NormalMove? b) =>
    a != null &&
    b != null &&
    a.from == b.from &&
    a.to == b.to &&
    a.promotion == b.promotion;

int? _mateInMoves(int score) {
  if (score > _mate - _maxPly) return ((_mate - score) + 1) >> 1;
  if (score < -_mate + _maxPly) return -(((_mate + score) + 1) >> 1);
  return null;
}

// ---- Evaluation -------------------------------------------------------------

const Map<Role, int> _value = {
  Role.pawn: 100,
  Role.knight: 320,
  Role.bishop: 330,
  Role.rook: 500,
  Role.queen: 900,
  Role.king: 0,
};

const Map<Role, int> _phaseWeight = {
  Role.pawn: 0,
  Role.knight: 1,
  Role.bishop: 1,
  Role.rook: 2,
  Role.queen: 4,
  Role.king: 0,
};

/// Static evaluation from the side-to-move's perspective. Material + piece-square
/// tables, with the king table tapered from midgame (stay home) to endgame
/// (centralise) by the amount of remaining material.
int _eval(Position pos) {
  var white = 0;
  var phase = 0;
  Square? whiteKing;
  Square? blackKing;
  for (final (square, piece) in pos.board.pieces) {
    if (piece.role == Role.king) {
      if (piece.color == Side.white) {
        whiteKing = square;
      } else {
        blackKing = square;
      }
      continue;
    }
    final v = _value[piece.role]! + _pst(_tableFor(piece.role), square, piece.color);
    white += piece.color == Side.white ? v : -v;
    phase += _phaseWeight[piece.role]!;
  }

  final t = phase > 24 ? 24 : phase;
  int kingValue(Square sq, Side side) =>
      (_pst(_pstKingMid, sq, side) * t + _pst(_pstKingEnd, sq, side) * (24 - t)) ~/ 24;
  if (whiteKing != null) white += kingValue(whiteKing, Side.white);
  if (blackKing != null) white -= kingValue(blackKing, Side.black);

  return pos.turn == Side.white ? white : -white;
}

/// Piece-square lookup. Tables are written rank-8-first (index 0 = a8); White
/// reads them rank-flipped, Black reads them straight (a vertical mirror).
int _pst(List<int> table, int square, Side side) {
  final rank = square >> 3, file = square & 7;
  final row = side == Side.white ? 7 - rank : rank;
  return table[row * 8 + file];
}

List<int> _tableFor(Role role) {
  switch (role) {
    case Role.pawn:
      return _pstPawn;
    case Role.knight:
      return _pstKnight;
    case Role.bishop:
      return _pstBishop;
    case Role.rook:
      return _pstRook;
    case Role.queen:
      return _pstQueen;
    case Role.king:
      return _pstKingMid;
  }
}

// Michniewski "simplified evaluation" tables.
const List<int> _pstPawn = [
  0, 0, 0, 0, 0, 0, 0, 0, //
  50, 50, 50, 50, 50, 50, 50, 50,
  10, 10, 20, 30, 30, 20, 10, 10,
  5, 5, 10, 25, 25, 10, 5, 5,
  0, 0, 0, 20, 20, 0, 0, 0,
  5, -5, -10, 0, 0, -10, -5, 5,
  5, 10, 10, -20, -20, 10, 10, 5,
  0, 0, 0, 0, 0, 0, 0, 0,
];

const List<int> _pstKnight = [
  -50, -40, -30, -30, -30, -30, -40, -50, //
  -40, -20, 0, 0, 0, 0, -20, -40,
  -30, 0, 10, 15, 15, 10, 0, -30,
  -30, 5, 15, 20, 20, 15, 5, -30,
  -30, 0, 15, 20, 20, 15, 0, -30,
  -30, 5, 10, 15, 15, 10, 5, -30,
  -40, -20, 0, 5, 5, 0, -20, -40,
  -50, -40, -30, -30, -30, -30, -40, -50,
];

const List<int> _pstBishop = [
  -20, -10, -10, -10, -10, -10, -10, -20, //
  -10, 0, 0, 0, 0, 0, 0, -10,
  -10, 0, 5, 10, 10, 5, 0, -10,
  -10, 5, 5, 10, 10, 5, 5, -10,
  -10, 0, 10, 10, 10, 10, 0, -10,
  -10, 10, 10, 10, 10, 10, 10, -10,
  -10, 5, 0, 0, 0, 0, 5, -10,
  -20, -10, -10, -10, -10, -10, -10, -20,
];

const List<int> _pstRook = [
  0, 0, 0, 0, 0, 0, 0, 0, //
  5, 10, 10, 10, 10, 10, 10, 5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  -5, 0, 0, 0, 0, 0, 0, -5,
  0, 0, 0, 5, 5, 0, 0, 0,
];

const List<int> _pstQueen = [
  -20, -10, -10, -5, -5, -10, -10, -20, //
  -10, 0, 0, 0, 0, 0, 0, -10,
  -10, 0, 5, 5, 5, 5, 0, -10,
  -5, 0, 5, 5, 5, 5, 0, -5,
  0, 0, 5, 5, 5, 5, 0, -5,
  -10, 5, 5, 5, 5, 5, 0, -10,
  -10, 0, 5, 0, 0, 0, 0, -10,
  -20, -10, -10, -5, -5, -10, -10, -20,
];

const List<int> _pstKingMid = [
  -30, -40, -40, -50, -50, -40, -40, -30, //
  -30, -40, -40, -50, -50, -40, -40, -30,
  -30, -40, -40, -50, -50, -40, -40, -30,
  -30, -40, -40, -50, -50, -40, -40, -30,
  -20, -30, -30, -40, -40, -30, -30, -20,
  -10, -20, -20, -20, -20, -20, -20, -10,
  20, 20, 0, 0, 0, 0, 20, 20,
  20, 30, 10, 0, 0, 10, 30, 20,
];

const List<int> _pstKingEnd = [
  -50, -40, -30, -20, -20, -30, -40, -50, //
  -30, -20, -10, 0, 0, -10, -20, -30,
  -30, -10, 20, 30, 30, 20, -10, -30,
  -30, -10, 30, 40, 40, 30, -10, -30,
  -30, -10, 30, 40, 40, 30, -10, -30,
  -30, -10, 20, 30, 30, 20, -10, -30,
  -30, -30, 0, 0, 0, 0, -30, -30,
  -50, -30, -30, -30, -30, -30, -30, -50,
];
