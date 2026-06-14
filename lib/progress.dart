import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// XP awarded for a clean random-puzzle solve, before the streak bonus.
const int _baseXp = 20;

/// Per-point streak bonus added to each clean solve (bigger streak → more XP).
const int _streakBonusPerPoint = 5;

/// XP required to advance from [level] to [level] + 1. Grows each level.
int xpToClearLevel(int level) => 100 + level * 25;

/// Persistent player progress: two independent streaks plus an XP/level system.
///
/// - [dailyStreak]: consecutive calendar days with any completed puzzle.
/// - [puzzleStreak]: consecutive clean random-puzzle solves, reset by any miss.
/// - [xp]/[level]: leveling driven by clean random solves, scaled by streak.
class ProgressStore extends ChangeNotifier {
  ProgressStore._(this._prefs) {
    dailyStreak = _prefs.getInt('dailyStreak') ?? 0;
    lastActiveDate = _prefs.getString('lastActiveDate');
    puzzleStreak = _prefs.getInt('puzzleStreak') ?? 0;
    bestPuzzleStreak = _prefs.getInt('bestPuzzleStreak') ?? 0;
    xp = _prefs.getInt('xp') ?? 0;
  }

  final SharedPreferences _prefs;

  late int dailyStreak;
  late String? lastActiveDate; // 'yyyy-mm-dd'
  late int puzzleStreak;
  late int bestPuzzleStreak;
  late int xp;

  static Future<ProgressStore> load() async {
    final prefs = await SharedPreferences.getInstance();
    return ProgressStore._(prefs);
  }

  Future<void> _save() async {
    await _prefs.setInt('dailyStreak', dailyStreak);
    if (lastActiveDate != null) {
      await _prefs.setString('lastActiveDate', lastActiveDate!);
    }
    await _prefs.setInt('puzzleStreak', puzzleStreak);
    await _prefs.setInt('bestPuzzleStreak', bestPuzzleStreak);
    await _prefs.setInt('xp', xp);
  }

  // ---- Level / XP -----------------------------------------------------------

  int get level {
    var lvl = 0;
    var rem = xp;
    while (rem >= xpToClearLevel(lvl)) {
      rem -= xpToClearLevel(lvl);
      lvl++;
    }
    return lvl;
  }

  /// XP accumulated within the current level.
  int get xpIntoLevel {
    var lvl = 0;
    var rem = xp;
    while (rem >= xpToClearLevel(lvl)) {
      rem -= xpToClearLevel(lvl);
      lvl++;
    }
    return rem;
  }

  /// XP needed to clear the current level.
  int get xpForCurrentLevel => xpToClearLevel(level);

  /// Progress through the current level in [0, 1].
  double get levelProgress => xpIntoLevel / xpForCurrentLevel;

  // ---- Daily streak ---------------------------------------------------------

  static String _dateKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// Marks today as active. Returns true if the daily streak just incremented
  /// (i.e. today is a newly-completed consecutive day) so callers can play the
  /// fire animation. Idempotent within the same calendar day.
  bool recordActiveDay([DateTime? now]) {
    final today = _dateKey(now ?? DateTime.now());
    if (lastActiveDate == today) return false;

    final yesterday =
        _dateKey((now ?? DateTime.now()).subtract(const Duration(days: 1)));
    dailyStreak = (lastActiveDate == yesterday) ? dailyStreak + 1 : 1;
    lastActiveDate = today;
    _save();
    notifyListeners();
    return true;
  }

  // ---- Puzzle streak / XP ---------------------------------------------------

  /// A clean random-puzzle solve: bumps the puzzle streak and awards XP scaled
  /// by the new streak. Returns the XP gained.
  int registerPuzzleSolvedClean() {
    puzzleStreak += 1;
    if (puzzleStreak > bestPuzzleStreak) bestPuzzleStreak = puzzleStreak;
    final gained = _baseXp + _streakBonusPerPoint * puzzleStreak;
    xp += gained;
    _save();
    notifyListeners();
    return gained;
  }

  /// A mistake on a random puzzle: resets the puzzle streak. Awards no XP.
  void registerPuzzleMistake() {
    if (puzzleStreak == 0) return;
    puzzleStreak = 0;
    _save();
    notifyListeners();
  }

  /// Test/util: wipe all progress.
  Future<void> reset() async {
    dailyStreak = 0;
    lastActiveDate = null;
    puzzleStreak = 0;
    bestPuzzleStreak = 0;
    xp = 0;
    await _prefs.clear();
    notifyListeners();
  }
}
