import 'package:flutter_test/flutter_test.dart';
import 'package:voicebridge/history.dart';

void main() {
  test('in-memory add + exportText (no IO)', () async {
    final h = History();
    // Skip load(); directly populate to avoid path_provider in unit test.
    h.turns.insertAll(0, [
      {'ts': '2026-05-26T08:00:00', 'from': 'en', 'to': 'vi', 'src': 'hello', 'dst': 'xin chào', 'glossary': false},
      {'ts': '2026-05-26T08:01:00', 'from': 'vi', 'to': 'en', 'src': 'cảm ơn', 'dst': 'thanks', 'glossary': true},
    ]);
    final txt = h.exportText();
    expect(txt, contains('hello'));
    expect(txt, contains('xin chào'));
    expect(txt, contains('⚑'));
    expect(txt, contains('vi→en'));
    expect(h.turns.length, 2);
  });
}
