// Unit tests for Puzzler's level/XP curve.

import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/progress.dart';

void main() {
  test('xpToClearLevel grows with level', () {
    expect(xpToClearLevel(0), 100);
    expect(xpToClearLevel(1), 125);
    expect(xpToClearLevel(4), 200);
    expect(xpToClearLevel(2) > xpToClearLevel(1), isTrue);
  });
}
