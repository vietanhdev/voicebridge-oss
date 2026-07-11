import 'package:flutter_test/flutter_test.dart';
import 'package:voicebridge/tts_normalize.dart';

void main() {
  test('percent + currency', () {
    expect(normalizeForTts('Up 25%', 'en'), contains('percent'));
    expect(normalizeForTts('Tăng 30%', 'vi'), contains('phần trăm'));
    expect(normalizeForTts(r'$50 fee', 'en'), contains('dollars'));
  });
  test('VN abbreviations + units', () {
    expect(normalizeForTts('TS. Nguyễn', 'vi'), startsWith('tiến sĩ'));
    expect(normalizeForTts('25°C today', 'en'), contains('degrees Celsius'));
  });
  test('all-caps acronyms spelled out', () {
    expect(normalizeForTts('Wear PPE', 'en'), contains('P P E'));
  });
  test('small integers spelled out per language', () {
    expect(normalizeForTts('5 minutes', 'en'), contains('five'));
    expect(normalizeForTts('Có 21 người', 'vi'), contains('hai mươi mốt'));
  });
}
