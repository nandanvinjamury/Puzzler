// Validates assets/fallback_puzzles.json against dartchess and rewrites it with
// only the puzzles whose FEN + setup move + full solution are all legal.
// Run: dart run tool/verify_puzzles.dart
import 'dart:convert';
import 'dart:io';
import 'package:dartchess/dartchess.dart' hide File;

void main() {
  final file = File('assets/fallback_puzzles.json');
  final rows = (jsonDecode(file.readAsStringSync()) as List)
      .cast<Map<String, dynamic>>();

  final good = <Map<String, dynamic>>[];
  for (final row in rows) {
    try {
      final fen = row['fen'] as String;
      final moves = (row['moves'] as String).split(' ');
      Position pos = Chess.fromSetup(Setup.parseFen(fen));
      for (final uci in moves) {
        final mv = Move.parse(uci);
        if (mv == null || !pos.isLegal(mv)) {
          throw 'illegal $uci';
        }
        pos = pos.play(mv);
      }
      good.add(row);
    } catch (e) {
      stderr.writeln('drop ${row['id']}: $e');
    }
  }

  file.writeAsStringSync(jsonEncode(good));
  stdout.writeln('verified ${good.length}/${rows.length} puzzles');
}
