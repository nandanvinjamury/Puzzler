import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:dartchess/dartchess.dart';

/// Lichess token from --dart-define. The placeholder counts as "no token".
const _envToken = String.fromEnvironment('LICHESS_TOKEN');
bool get _hasToken => _envToken.isNotEmpty && !_envToken.contains('xxxx');
Map<String, String> get _authHeaders =>
    _hasToken ? {'Authorization': 'Bearer $_envToken'} : const {};

/// A puzzle resolved into a ready-to-play state. Serializable (normalized form)
/// so it can be cached on device.
class Puzzle {
  Puzzle({
    required this.id,
    required this.rating,
    required this.themes,
    required this.initialPosition,
    required this.orientation,
    required this.setupMove,
    required this.solution,
  });

  final String id;
  final int rating;
  final List<String> themes;
  final Position initialPosition;
  final Side orientation;
  final Move? setupMove;
  final List<String> solution;

  /// Normalized form: the solver-to-move FEN, the highlight move, and solution.
  Map<String, dynamic> toJson() => {
        'id': id,
        'rating': rating,
        'themes': themes,
        'fen': initialPosition.fen,
        'setup': setupMove?.uci,
        'solution': solution,
      };

  factory Puzzle.fromJson(Map<String, dynamic> m) {
    final setup = m['setup'] as String?;
    final pos = Chess.fromSetup(Setup.parseFen(m['fen'] as String));
    return Puzzle(
      id: m['id'].toString(),
      rating: (m['rating'] as num).toInt(),
      themes: (m['themes'] as List).map((e) => e.toString()).toList(),
      initialPosition: pos,
      orientation: pos.turn,
      setupMove: setup != null ? Move.parse(setup) : null,
      solution: (m['solution'] as List).map((e) => e.toString()).toList(),
    );
  }

  /// Builds a puzzle from a Lichess puzzle-DB row, where `moves[0]` is the
  /// opponent's setup move and the rest is the solution.
  factory Puzzle.fromDbRow(Map<String, dynamic> row) {
    final moves = (row['moves'] as String).split(' ');
    final pos0 = Chess.fromSetup(Setup.parseFen(row['fen'] as String));
    final setup = Move.parse(moves.first)!;
    final start = pos0.play(setup);
    return Puzzle(
      id: row['id'].toString(),
      rating: (row['rating'] as num).toInt(),
      themes: (row['themes'] as List).map((e) => e.toString()).toList(),
      initialPosition: start,
      orientation: start.turn,
      setupMove: setup,
      solution: moves.sublist(1),
    );
  }
}

/// Parses the API `{game, puzzle}` payload, replaying `game.pgn` to the puzzle
/// start (solver to move).
Puzzle _parseApiPuzzle(Map<String, dynamic> m) {
  final game = m['game'] as Map<String, dynamic>;
  final puzzle = m['puzzle'] as Map<String, dynamic>;

  final sanMoves = (game['pgn'] as String)
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty)
      .toList();

  Position pos = Chess.initial;
  Move? last;
  for (final san in sanMoves) {
    final mv = pos.parseSan(san);
    if (mv == null) throw 'unparseable SAN "$san" in puzzle pgn';
    pos = pos.play(mv);
    last = mv;
  }

  return Puzzle(
    id: puzzle['id'].toString(),
    rating: (puzzle['rating'] as num).toInt(),
    themes: (puzzle['themes'] as List).map((e) => e.toString()).toList(),
    initialPosition: pos,
    orientation: pos.turn,
    setupMove: last,
    solution:
        (puzzle['solution'] as List).map((e) => e.toString()).toList(),
  );
}

/// GET with auth header (when available) and 429 backoff. The puzzle endpoints
/// rate-limit bursts, so callers must space requests out.
Future<Puzzle> _fetch(String url) async {
  var backoff = const Duration(seconds: 1);
  for (var attempt = 0;; attempt++) {
    final res = await http.get(Uri.parse(url), headers: _authHeaders);
    if (res.statusCode == 200) {
      return _parseApiPuzzle(jsonDecode(res.body) as Map<String, dynamic>);
    }
    if (res.statusCode == 429 && attempt < 2) {
      await Future.delayed(backoff);
      backoff *= 2;
      continue;
    }
    if (res.statusCode == 429) {
      throw 'Lichess is rate-limiting puzzle requests — wait a minute and retry.';
    }
    throw 'GET $url -> ${res.statusCode}: ${res.body}';
  }
}

/// The Lichess daily puzzle (not aggressively rate-limited).
Future<Puzzle> fetchDailyPuzzle() =>
    _fetch('https://lichess.org/api/puzzle/daily');

/// A single random puzzle. Space these out by user solve time to stay under the
/// rate limit. [exclude] retries to avoid repeats.
Future<Puzzle> fetchRandomPuzzle({Set<String> exclude = const {}}) async {
  for (var i = 0; i < 3; i++) {
    final p = await _fetch('https://lichess.org/api/puzzle/next');
    if (!exclude.contains(p.id)) return p;
    await Future.delayed(const Duration(milliseconds: 1500));
  }
  return _fetch('https://lichess.org/api/puzzle/next');
}
