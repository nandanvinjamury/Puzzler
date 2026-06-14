// Verifies the analysis board paints engine "best line" arrows. Review mode
// pre-plays the solution and opens straight into analysis, so the board kicks
// off the background engine immediately.
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/lichess.dart';
import 'package:puzzler/puzzle_board.dart';

void main() {
  testWidgets('engine paints best-line arrows in analysis', (tester) async {
    await tester.runAsync(() async {
      // White to move with Ra8# available; review mode plays it then resets to
      // the start, where the engine should arrow a1->a8.
      final pos = Chess.fromSetup(Setup.parseFen('6k1/5ppp/8/8/8/8/8/R6K w - - 0 1'));
      final puzzle = Puzzle(
        id: 'arrowtest',
        rating: 1000,
        themes: const [],
        initialPosition: pos,
        orientation: Side.white,
        setupMove: null,
        solution: const ['a1a8'],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              height: 640,
              child: PuzzleBoard(puzzle: puzzle, reviewMode: true),
            ),
          ),
        ),
      );
      await tester.pump(); // fires the post-frame engine kick

      // Let the background isolate return and the arrows paint.
      var found = false;
      for (var i = 0; i < 60 && !found; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        found = find.byType(BoardShapeWidget).evaluate().isNotEmpty;
      }
      expect(found, isTrue,
          reason: 'engine should paint at least one best-line arrow');
    });
  });
}
