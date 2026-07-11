// Data-driven sweeps: large case sets per feature to flush out edge cases.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicebridge/glossary.dart';
import 'package:voicebridge/history.dart';
import 'package:voicebridge/tts_normalize.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── TTS NORMALIZATION ────────────────────────────────────────────────────
  group('TTS normalize — EN cases', () {
    final cases = {
      '0 errors': 'zero', '1 alarm': 'one', '17 items': 'seventeen',
      '21 boxes': 'twenty-one', '50 percent off': 'fifty', '99 bottles': 'ninety-nine',
      '100 units': 'one hundred', '101 items': 'one hundred one',
      '250 packs': 'two hundred fifty', '999 max': 'nine hundred ninety-nine',
      'Up 25%': 'percent', r'$50 fee': 'dollars',
      '25°C today': 'degrees Celsius', 'Wear PPE': 'P P E',
      'Dr. Nguyen': 'Doctor', 'Inc. and Ltd.': 'Incorporated',
    };
    cases.forEach((input, expected) {
      test('"$input" → contains "$expected"', () =>
          expect(normalizeForTts(input, 'en'), contains(expected)));
    });
  });

  group('TTS normalize — VN cases', () {
    final cases = {
      'Tăng 30%': 'phần trăm', 'TS. Lan': 'tiến sĩ', 'GS. Minh': 'giáo sư',
      'TP. HCM': 'thành phố', '25°C nóng': 'độ C',
      'Có 5 người': 'năm', 'Có 21 người': 'hai mươi mốt',
      'Có 15 cái': 'mười lăm', 'Có 50 cái': 'năm mươi',
      'Có 100 hộp': 'một trăm', 'Có 105 hộp': 'lẻ năm',
      'Có 250 lít': 'hai trăm', '500 kg': 'năm trăm',
    };
    cases.forEach((input, expected) {
      test('"$input" → contains "$expected"', () =>
          expect(normalizeForTts(input, 'vi'), contains(expected)));
    });
  });

  group('TTS normalize — KO cases (sino numbers + units)', () {
    final cases = {
      '5 명': '다섯', // native modifier (counter-bound) — was incorrect sino in v1 '21 개': '이십일', '100 개': '일백', '105 개': '일백영오',
      '오늘 25°C': '섭씨', '50%': '퍼센트',
    };
    cases.forEach((input, expected) {
      test('"$input" → contains "$expected"', () =>
          expect(normalizeForTts(input, 'ko'), contains(expected)));
    });
  });

  group('TTS normalize — ZH cases', () {
    final cases = {
      '5个': '五', '21个': '二十一', '100个': '一百', '105个': '一百零五',
      '今天 25°C': '摄氏度', '30%': '百分',
    };
    cases.forEach((input, expected) {
      test('"$input" → contains "$expected"', () =>
          expect(normalizeForTts(input, 'zh'), contains(expected)));
    });
  });

  group('TTS extended rules (KO counters / ZH 两 / year-pair / money)', () {
    test('KO 3개→세 개 (native modifier)', () => expect(normalizeForTts('3개 있어', 'ko'), contains('세 개')));
    test('KO 2명→두 명', () => expect(normalizeForTts('2명', 'ko'), contains('두 명')));
    test('KO 5권→다섯 권', () => expect(normalizeForTts('5권 책', 'ko'), contains('다섯 권')));
    test('KO 100개 (>10) → sino fallback', () => expect(normalizeForTts('100개', 'ko'), allOf(contains('일백'), contains('개'))));
    test('ZH 2个→两个 (measure word)', () => expect(normalizeForTts('我有2个', 'zh'), contains('两个')));
    test('ZH 200本→两百本', () => expect(normalizeForTts('200本书', 'zh'), contains('两百本')));
    test('ZH 二十 stays (no measure word)', () => expect(normalizeForTts('20', 'zh'), '二十'));
    test('EN year 2026→twenty twenty-six', () => expect(normalizeForTts('Born in 2026', 'en'), contains('twenty twenty-six')));
    test('EN year 2005→twenty oh five', () => expect(normalizeForTts('In 2005', 'en'), contains('twenty oh five')));
    test('EN year 1999→nineteen ninety-nine', () => expect(normalizeForTts('Since 1999', 'en'), contains('nineteen ninety-nine')));
    test('VND 3000đ→spelled đồng', () => expect(normalizeForTts('Giá 3000đ', 'vi'), allOf(contains('đồng'), contains('ba'))));
    test('VND 1500 VNĐ', () => expect(normalizeForTts('1500 VNĐ', 'vi'), contains('đồng')));
    test('KRW ₩3500 (prefix)', () => expect(normalizeForTts('₩3500', 'ko'), contains('원')));
  });

  group('TTS rules from primary sources (NeMo/Paddle/Coqui/g2pK)', () {
    test('email → at + dot', () => expect(normalizeForTts('a.b@x.com', 'en'),
        allOf(contains(' at '), contains(' dot '))));
    test('URL spells scheme + slash + dot', () => expect(normalizeForTts('https://a.com/x', 'en'),
        allOf(contains('h t t p s'), contains(' slash '), contains(' dot '))));
    test('version v1.2.3 expanded', () => expect(normalizeForTts('Release v1.2.3', 'en'),
        allOf(contains('v one dot two dot three'))));
    test('EN ordinal 2nd→second', () => expect(normalizeForTts('Win 2nd place', 'en'), contains('second')));
    test('EN ordinal 13th→thirteenth', () => expect(normalizeForTts('On 13th', 'en'), contains('thirteenth')));
    test('VI dotted thousand 10.000→mười nghìn', () => expect(normalizeForTts('10.000 đồng', 'vi'), contains('nghìn')));
    test('EN fraction 1/5→over', () => expect(normalizeForTts('1/5 cup', 'en'), contains('over')));
    test('VI fraction 1/5→phần', () => expect(normalizeForTts('1/5 cốc', 'vi'), contains('phần')));
    test('ZH fraction 1/5→分之', () => expect(normalizeForTts('1/5 杯', 'zh'), contains('分之')));
  });

  group('TTS extensions — thousands/decimals/ranges/times/commas', () {
    test('EN thousands 1234', () => expect(normalizeForTts('1234 items', 'en'), contains('thousand')));
    test('VN thousands 1500', () => expect(normalizeForTts('1500 đồng', 'vi'), contains('nghìn')));
    test('EN comma-grouping 1,234', () => expect(normalizeForTts('Saw 1,234 boxes', 'en'), contains('thousand')));
    test('EN decimal 1.5', () => expect(normalizeForTts('Add 1.5 kg', 'en'), contains('point')));
    test('VN decimal 1.5', () => expect(normalizeForTts('Thêm 1.5 kg', 'vi'), contains('phẩy')));
    test('EN range 5-10', () => expect(normalizeForTts('Wait 5-10 minutes', 'en'), contains(' to ')));
    test('VN range 5-10', () => expect(normalizeForTts('Chờ 5-10 phút', 'vi'), contains(' đến ')));
    test('VN time 08:30', () => expect(normalizeForTts('Họp lúc 08:30', 'vi'), contains('giờ')));
    test('KO time 08:30', () => expect(normalizeForTts('회의 08:30', 'ko'), contains('시')));
  });

  test('TTS normalize idempotency: re-running doesn\'t cascade', () {
    const s = 'Wear PPE near 5 forklifts';
    expect(normalizeForTts(normalizeForTts(s, 'en'), 'en'),
        normalizeForTts(s, 'en'));
  });

  // ── GLOSSARY ENFORCEMENT (many sentences) ────────────────────────────────
  group('Glossary apply — factory en→vi', () {
    final g = Glossary(Domain.factory);
    final sentences = {
      'Hit the emergency stop now': 'dừng khẩn cấp',
      'Wear your safety helmet': 'mũ bảo hộ',
      'Move the forklift back': 'xe nâng',
      'Follow lockout-tagout': 'khóa và treo thẻ',
      'Put on PPE before entry': 'đồ bảo hộ cá nhân',
    };
    sentences.forEach((src, locked) {
      test('"$src" enforces "$locked"', () {
        final (out, en) = g.apply(src, 'Translated WITHOUT locked term.', 'en', 'vi');
        expect(en, isTrue);
        expect(out, contains(locked));
      });
    });
  });

  test('Glossary persistence simulation (user-add → reload)', () async {
    SharedPreferences.setMockInitialValues({});
    final g1 = Glossary(Domain.factory);
    await g1.load();
    final before = g1.entries.length;
    g1.add(GlossaryEntry(src: 'VinFast', dst: 'Vin Fát', srcLang: 'en', dstLang: 'vi'));
    expect(g1.entries.length, before + 1);
    // simulate restart
    final g2 = Glossary(Domain.factory);
    await g2.load();
    expect(g2.entries.any((e) => e.src == 'VinFast'), isTrue);
  });

  test('Glossary user-add survives domain swap', () async {
    SharedPreferences.setMockInitialValues({});
    final g = Glossary(Domain.factory);
    await g.load();
    g.add(GlossaryEntry(src: 'X', dst: 'Y', srcLang: 'en', dstLang: 'vi'));
    g.setDomain(Domain.medical);
    expect(g.entries.any((e) => e.src == 'X'), isTrue); // user term sticks
    expect(g.entries.any((e) => e.src == 'allergy'), isTrue);
    expect(g.entries.any((e) => e.src == 'forklift'), isFalse);
  });

  // ── HISTORY export format ────────────────────────────────────────────────
  test('History export handles 50 turns + utf8 + glossary marks', () {
    final h = History();
    for (var i = 0; i < 50; i++) {
      h.turns.insert(0, {
        'ts': '2026-05-26T08:${(i % 60).toString().padLeft(2, '0')}:00',
        'from': 'vi', 'to': 'en', 'src': 'Mẫu $i với chữ tiếng Việt',
        'dst': 'Sample $i with VN chars', 'glossary': i.isEven,
      });
    }
    final txt = h.exportText();
    expect(txt.split('\n\n').length, 50);
    expect(txt, contains('Mẫu 49'));
    expect(txt, contains('Tiếng'.substring(1, 4))); // 'iến' — utf8 round-trip
  });
}
