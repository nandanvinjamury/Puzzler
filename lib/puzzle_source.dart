import 'dart:convert';
import 'dart:math';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';
import 'lichess.dart';

/// On-device cache of puzzles fetched ahead of time, so the alarm never has to
/// hit the rate-limited API live. Refills opportunistically while the app is
/// open and is drained by the alarm session.
class PuzzleCache {
  PuzzleCache(this._prefs);
  final SharedPreferences _prefs;

  static const _key = 'puzzleCache';
  static const _target = 20;
  static const _maxStore = 60;
  bool _refilling = false;

  static Future<PuzzleCache> load() async =>
      PuzzleCache(await SharedPreferences.getInstance());

  List<Map<String, dynamic>> _read() {
    final raw = _prefs.getString(_key);
    if (raw == null) return [];
    return (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  }

  Future<void> _write(List<Map<String, dynamic>> list) =>
      _prefs.setString(_key, jsonEncode(list));

  int get size => _read().length;

  /// Removes and returns a *random* cached puzzle whose id isn't in [exclude].
  /// Random (not FIFO) so the alarm doesn't serve the same puzzles in the same
  /// order every morning.
  Future<Puzzle?> take({Set<String> exclude = const {}}) async {
    final list = _read();
    final candidates = <int>[
      for (var i = 0; i < list.length; i++)
        if (!exclude.contains(list[i]['id'])) i,
    ];
    if (candidates.isEmpty) return null;
    final row = list.removeAt(candidates[_rng.nextInt(candidates.length)]);
    await _write(list);
    try {
      return Puzzle.fromJson(row);
    } catch (_) {
      return null;
    }
  }

  Future<void> add(Puzzle p) async {
    final list = _read();
    if (list.any((m) => m['id'] == p.id)) return;
    list.add(p.toJson());
    if (list.length > _maxStore) {
      list.removeRange(0, list.length - _maxStore);
    }
    await _write(list);
  }

  /// Fetches puzzles from the API (spaced out) until [target] is reached or the
  /// API rate-limits / fails. Fire-and-forget; safe to call repeatedly.
  Future<void> refill({int target = _target}) async {
    if (_refilling) return;
    _refilling = true;
    try {
      while (size < target) {
        final seen = _read().map((m) => m['id'] as String).toSet();
        try {
          final p = await fetchRandomPuzzle(exclude: seen);
          // /api/puzzle/next keeps returning the same "next" puzzle until it's
          // solved on Lichess; once we see a repeat, stop (don't spin the API).
          if (seen.contains(p.id)) break;
          await add(p);
        } catch (_) {
          break; // rate-limited or offline — retry on the next call
        }
        await Future.delayed(const Duration(seconds: 3));
      }
    } finally {
      _refilling = false;
    }
  }
}

// ---- Bundled offline fallback -----------------------------------------------

List<Puzzle>? _bundled;

/// Loads the ~60 bundled fallback puzzles shipped as an asset.
Future<List<Puzzle>> loadBundledPuzzles() async {
  if (_bundled != null) return _bundled!;
  final raw = await rootBundle.loadString('assets/fallback_puzzles.json');
  final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
  _bundled = [
    for (final r in rows)
      if (_tryDbRow(r) case final p?) p,
  ];
  return _bundled!;
}

Puzzle? _tryDbRow(Map<String, dynamic> row) {
  try {
    return Puzzle.fromDbRow(row);
  } catch (_) {
    return null;
  }
}

final _rng = Random();

Future<Puzzle> _randomBundled({Set<String> exclude = const {}}) async {
  final all = await loadBundledPuzzles();
  final pool = all.where((p) => !exclude.contains(p.id)).toList();
  final list = pool.isEmpty ? all : pool;
  return list[_rng.nextInt(list.length)];
}

// ---- Acquisition chain ------------------------------------------------------

/// Random puzzle for the alarm: cache → live API (only if genuinely new) →
/// bundled fallback. The bundled fallback guarantees a puzzle the session hasn't
/// shown yet, so the three random stages are never the same puzzle.
Future<Puzzle> acquireRandomPuzzle(PuzzleCache cache,
    {Set<String> exclude = const {}}) async {
  final cached = await cache.take(exclude: exclude);
  if (cached != null) return cached;
  try {
    final p = await fetchRandomPuzzle(exclude: exclude);
    // /api/puzzle/next repeats the same puzzle until it's solved on Lichess —
    // only accept it if we haven't already shown it this session.
    if (!exclude.contains(p.id)) return p;
  } catch (_) {
    // fall through to the bundled set
  }
  return _randomBundled(exclude: exclude);
}

/// Daily puzzle, falling back to a bundled puzzle when offline.
Future<Puzzle> acquireDailyPuzzle({Set<String> exclude = const {}}) async {
  try {
    return await fetchDailyPuzzle();
  } catch (_) {
    return _randomBundled(exclude: exclude);
  }
}
