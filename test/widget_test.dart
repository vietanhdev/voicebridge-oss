import 'package:flutter_test/flutter_test.dart';

import 'package:voicebridge/glossary.dart';

void main() {
  test('glossary surfaces a locked safety term when MT omits it', () {
    final g = Glossary();
    final (text, enforced) =
        g.apply('please hit the emergency stop', 'vui lòng nhấn nút', 'en', 'vi');
    expect(enforced, isTrue);
    expect(text.contains('dừng khẩn cấp'), isTrue);
  });
}
