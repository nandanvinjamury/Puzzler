// Verifies the daily (flame) and puzzle (bolt) streak badges are standardized:
// same icon footprint, same gap, same number. Both icons are CustomPaints now,
// so they render in goldens (the Material bolt glyph did not).
//   flutter test --update-goldens test/streak_cards_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/theme.dart';
import 'package:puzzler/widgets.dart';

void main() {
  testWidgets('streak cards are standardized', (tester) async {
    Widget card(String label, Widget badge) => Container(
          width: 160,
          padding: const EdgeInsets.all(16),
          margin: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(
                      color: AppColors.textMuted, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              badge,
            ],
          ),
        );

    await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              card(
                'Daily streak',
                const StreakBadge(
                  icon: AnimatedFlame(size: 34, streak: 8),
                  count: 8,
                  active: true,
                ),
              ),
              card(
                'Puzzle streak',
                const StreakBadge(
                  icon: LightningBolt(size: 34),
                  count: 8,
                  active: true,
                ),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    await expectLater(
        find.byType(Row).first, matchesGoldenFile('goldens/streak_cards.png'));
  });
}
