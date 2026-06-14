// Visual check of the engine arrows. Regenerate with:
//   flutter test --update-goldens test/engine_arrows_golden_test.dart
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/lichess.dart';
import 'package:puzzler/puzzle_board.dart';

void main() {
  testWidgets('engine arrows golden', (tester) async {
    await tester.runAsync(() async {
      // A quiet middlegame-ish position so both a best move and a reply arrow show.
      final pos = Chess.fromSetup(
          Setup.parseFen('r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4'));
      final puzzle = Puzzle(
        id: 'arrowgolden',
        rating: 1500,
        themes: const [],
        initialPosition: pos,
        orientation: Side.white,
        setupMove: null,
        solution: const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          debugShowCheckedModeBanner: false,
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                height: 360,
                child: PuzzleBoard(puzzle: puzzle, reviewMode: true),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      for (var i = 0; i < 60; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.byType(BoardShapeWidget).evaluate().isNotEmpty) break;
      }
    });
    // matchesGoldenFile uses runAsync internally, so capture outside the block.
    await tester.pump();
    await expectLater(
        find.byType(PuzzleBoard), matchesGoldenFile('goldens/engine_arrows.png'));
  });
}
