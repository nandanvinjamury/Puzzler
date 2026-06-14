// Unit tests for the Sleep as Android captcha launch model.
import 'package:flutter_test/flutter_test.dart';
import 'package:puzzler/captcha.dart';

void main() {
  test('fromMap reads preview + difficulty with sane defaults', () {
    final a = CaptchaLaunch.fromMap(const {'isPreview': true, 'difficulty': 2});
    expect(a.isPreview, isTrue);
    expect(a.difficulty, 2);

    final b = CaptchaLaunch.fromMap(const {});
    expect(b.isPreview, isFalse);
    expect(b.difficulty, 1);
  });
}
