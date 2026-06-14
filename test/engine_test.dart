// Sanity checks for the offline hint engine: it must find the obvious move and,
// with more depth, see short forced mates.
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/engine.dart';

void main() {
  test('finds a back-rank mate in one', () {
    // White: Ra1, Kh1. Black: Kg8 boxed in by its own f7/g7/h7 pawns. Ra8#.
    final line = engineLine('6k1/5ppp/8/8/8/8/8/R6K w - - 0 1');
    expect(line.best, 'a1a8');
    expect(line.mateIn, 1);
    expect(line.reply, isNull); // it's mate — no reply
  });

  test('sees a forced mate in two (needs depth > 1)', () {
    // White Kf6 + Qf1 vs lone Kh8. 1.Qf7 Kh7 (forced) 2.Qg7#. No mate in one.
    final line = engineLine('7k/8/5K2/8/8/8/8/5Q2 w - - 0 1', maxDepth: 4);
    expect(line.mateIn, 2);
    expect(line.best, isNotNull);
  });

  test('grabs a hanging queen and values the material', () {
    // White rook on d1 can take the undefended black queen on d5.
    final line = engineLine('4k3/8/8/3q4/8/8/8/3RK3 w - - 0 1');
    expect(line.best, 'd1d5');
    expect(line.scoreCp, greaterThan(300)); // clearly winning — up a rook
  });

  test('returns a legal move and a reply from the opening', () {
    final line = engineLine(
        'rnbqkbnr/pppppppp/8/8/8/8/PPPPPPPP/RNBQKBNR w KQkq - 0 1',
        maxDepth: 4);
    expect(line.best, isNotNull);
    expect(line.best!.length, greaterThanOrEqualTo(4));
    expect(line.reply, isNotNull); // opponent has a reply
  });
}
