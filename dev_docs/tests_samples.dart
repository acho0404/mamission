
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Budget rounding', () {
    final euros = 19.99;
    expect((euros * 100).round(), 1999);
  });
}
