// Unit tests for the streak flame colour cadence.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/widgets.dart';

void main() {
  test('dead streak is a grey ember', () {
    expect(flameColors(0).outer, const Color(0xFF6B6864));
  });

  test('a one-day streak starts yellow', () {
    expect(flameColors(1).outer, const Color(0xFFFFD60A));
  });

  test('the inner flame is a lighter tint of the outer', () {
    final c = flameColors(40); // orange band
    expect(c.inner, isNot(c.outer));
    // Lighter ⇒ higher luminance than the outer hue.
    expect(c.inner.computeLuminance(), greaterThan(c.outer.computeLuminance()));
  });

  test('the cycle advances through the hues over the year', () {
    // ~36.5 days per colour: day 1 yellow, ~day 38 orange, ~day 75 red.
    expect(flameColors(1).outer, const Color(0xFFFFD60A));
    expect(flameColors(40).outer, isNot(flameColors(1).outer));
  });

  test('after a full year it wraps back to yellow', () {
    // 365 days / 10 colours = 36.5 days each, so streak 366 lands on yellow again.
    expect(flameColors(366).outer, flameColors(1).outer);
  });
}
