// Verifies the analysis board layout in a phone-shaped box: engine chip pinned
// at the top, board high up (small top gap), the caption/footer vertically
// centred in the gap above the move bar, and the move bar at the very bottom.
//   flutter test --update-goldens test/board_layout_golden_test.dart
import 'package:chessground/chessground.dart';
import 'package:dartchess/dartchess.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/lichess.dart';
import 'package:puzzler/puzzle_board.dart';
import 'package:puzzler/theme.dart';

void main() {
  testWidgets('board layout golden', (tester) async {
    // Approximate a phone's puzzle area (portrait) so the golden is representative.
    await tester.binding.setSurfaceSize(const Size(412, 680));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      final pos = Chess.fromSetup(Setup.parseFen(
          'r1bqkb1r/pppp1ppp/2n2n2/4p3/2B1P3/5N2/PPPP1PPP/RNBQK2R w KQkq - 4 4'));
      final puzzle = Puzzle(
        id: 'layout',
        rating: 1500,
        themes: const [],
        initialPosition: pos,
        orientation: Side.white,
        setupMove: null,
        solution: const [],
      );

      await tester.pumpWidget(MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppColors.bg,
          body: SafeArea(
            child: PuzzleBoard(
              puzzle: puzzle,
              reviewMode: true,
              // Mimics the solved footer: caption on the left, advance button right.
              footer: Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text('+25 XP',
                          style: TextStyle(
                              fontSize: 15, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: () {},
                      style: FilledButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: const EdgeInsets.all(14),
                        minimumSize: const Size(52, 52),
                      ),
                      child: const Icon(Icons.arrow_forward, size: 24),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      for (var i = 0; i < 40; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
        if (find.byType(BoardShapeWidget).evaluate().isNotEmpty) break;
      }
    });
    await tester.pump();
    await expectLater(
        find.byType(PuzzleBoard), matchesGoldenFile('goldens/board_layout.png'));
  });
}
