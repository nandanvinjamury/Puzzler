import 'package:flutter/material.dart';
import 'package:dartchess/dartchess.dart';
import '../lichess.dart';
import '../puzzle_board.dart';
import '../theme.dart';

/// Read-only review of an already-solved puzzle: the solution is pre-played and
/// the board opens as an analysis board (step through moves, try alternatives).
class PuzzleReviewScreen extends StatelessWidget {
  const PuzzleReviewScreen(
      {super.key, required this.puzzle, required this.label});
  final Puzzle puzzle;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Integrated back control (no app bar) + the review label.
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 0),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    color: AppColors.textMuted,
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  Expanded(
                    child: Text('Review · $label',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16)),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '#${puzzle.id} · rating ${puzzle.rating} · '
                  '${puzzle.orientation == Side.white ? 'White' : 'Black'} to move',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            ),
            Expanded(
              child: PuzzleBoard(
                puzzle: puzzle,
                reviewMode: true,
                footer: const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 8),
                  child: Text(
                      'Play your own moves — the green arrow is the engine’s best.',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 12)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
