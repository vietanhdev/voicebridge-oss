import 'package:flutter_test/flutter_test.dart';
import 'package:voicebridge/glossary.dart';

void main() {
  test('factory domain enforces safety terms', () {
    final g = Glossary(Domain.factory);
    expect(g.entries.any((e) => e.src == 'emergency stop'), isTrue);
    final (out, en) = g.apply('Please hit the emergency stop now', 'Xin hãy nhấn nút dừng ngay', 'en', 'vi');
    expect(en, isTrue);
    expect(out, contains('dừng khẩn cấp'));
  });

  test('domain swap replaces the pack', () {
    final g = Glossary(Domain.factory);
    expect(g.entries.any((e) => e.src == 'forklift'), isTrue);
    g.setDomain(Domain.medical);
    expect(g.entries.any((e) => e.src == 'forklift'), isFalse);
    expect(g.entries.any((e) => e.src == 'allergy'), isTrue);
    g.setDomain(Domain.construction);
    expect(g.entries.any((e) => e.src == 'scaffold'), isTrue);
    g.setDomain(Domain.general);
    expect(g.entries, isEmpty);
  });

  test('apply does not enforce if locked target already present', () {
    final g = Glossary(Domain.factory);
    final (_, en) = g.apply('emergency stop', 'dừng khẩn cấp', 'en', 'vi');
    expect(en, isFalse);
  });
}
