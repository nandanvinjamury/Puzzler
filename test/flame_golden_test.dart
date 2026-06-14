// Renders the streak flame across the colour cycle so the shape (round bottom,
// pointy top, lighter nested inner flame) and the yellow→…→gold→yellow cadence
// can be eyeballed. Regenerate the image with:
//   flutter test --update-goldens test/flame_golden_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/theme.dart';
import 'package:puzzler/widgets.dart';

void main() {
  testWidgets('flame shape and colour cadence', (tester) async {
    // streak 0 (dead ember) then one sample per ~36.5-day colour band, then a
    // wrap-around sample (>365) which should be yellow again.
    const streaks = [0, 1, 40, 75, 112, 148, 185, 222, 258, 295, 330, 365, 400];
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: AppColors.bg,
          body: Center(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: [
                for (final s in streaks)
                  SizedBox(
                    width: 72,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedFlame(size: 64, streak: s),
                        const SizedBox(height: 4),
                        Text('$s',
                            style: const TextStyle(color: AppColors.text)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await expectLater(
      find.byType(Scaffold),
      matchesGoldenFile('goldens/flames.png'),
    );
  });
}
