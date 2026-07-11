/// TTS text normalization (frontend) — applied before flutter_tts.speak.
///
/// Why: raw MT/OCR output contains numbers, %, currency, acronyms, units,
/// abbreviations that off-the-shelf TTS voices mispronounce or spell out
/// awkwardly. This is a minimal practical normalizer covering the most common
/// hazards in factory/safety text. Full-grade TN is large (Google
/// sparrowhawk, NeMo, ESPnet TN) — out of scope on-device.
///
/// Pipeline: percent → currency → units → abbreviations → all-caps acronyms
/// → small integers → done. Stays language-aware via a `lang` code.
library;

const _abbr = {
  'en': {
    'Mr.': 'Mister', 'Mrs.': 'Misses', 'Dr.': 'Doctor', 'Inc.': 'Incorporated',
    'Ltd.': 'Limited', 'Co.': 'Company', 'St.': 'Street', 'Ave.': 'Avenue',
    'vs.': 'versus', 'etc.': 'et cetera', 'e.g.': 'for example', 'i.e.': 'that is',
  },
  'vi': {
    'TS.': 'tiến sĩ', 'GS.': 'giáo sư', 'BS.': 'bác sĩ', 'Cty': 'công ty',
    'TP.': 'thành phố', 'P.': 'phường', 'Q.': 'quận', 'HCM': 'hồ chí minh',
  },
};

const _units = {
  'en': {'°C': ' degrees Celsius', '°F': ' degrees Fahrenheit', 'km/h': ' kilometers per hour', 'mph': ' miles per hour'},
  'vi': {'°C': ' độ C', '°F': ' độ F', 'km/h': ' ki lô mét trên giờ'},
  'ko': {'°C': ' 섭씨', '°F': ' 화씨', 'km/h': ' 시속 킬로미터'},
  'zh': {'°C': ' 摄氏度', '°F': ' 华氏度', 'km/h': ' 公里每小时'},
  '_': {'kg': ' kg', 'cm': ' cm', 'mm': ' mm', 'mg': ' mg'},
};

const _percent = {'en': ' percent', 'vi': ' phần trăm', 'ko': ' 퍼센트', 'zh': ' 百分'};
const _currency = {
  '\$': {'en': ' dollars', 'vi': ' đô la', 'ko': ' 달러', 'zh': ' 美元'},
  '₫': {'vi': ' đồng', 'en': ' Vietnamese dong'},
  '€': {'en': ' euros', 'vi': ' euro'},
  '₩': {'ko': ' 원', 'en': ' Korean won'},
};

const _viNum = ['không', 'một', 'hai', 'ba', 'bốn', 'năm', 'sáu', 'bảy', 'tám', 'chín'];
const _enNum = ['zero', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine'];
const _koNum = ['영', '일', '이', '삼', '사', '오', '육', '칠', '팔', '구']; // sino-Korean (numbers/money)
const _zhNum = ['零', '一', '二', '三', '四', '五', '六', '七', '八', '九'];

String _spellKoZh(int n, List<String> d, String tenWord, String hundredWord) {
  // CJK-style: 십/百, 20=二十, 21=二十一, 100=一百, 105=一百零五.
  if (n < 10) return d[n];
  if (n < 100) {
    final t = n ~/ 10, u = n % 10;
    final tens = t == 1 ? tenWord : '${d[t]}$tenWord';
    return u == 0 ? tens : '$tens${d[u]}';
  }
  final h = n ~/ 100, rest = n % 100;
  final base = '${d[h]}$hundredWord';
  if (rest == 0) return base;
  if (rest < 10) return '$base${d[0]}${d[rest]}'; // 零 between hundreds and units
  return '$base${_spellKoZh(rest, d, tenWord, hundredWord)}';
}

const _thousand = {'en': 'thousand', 'vi': 'nghìn', 'ko': '천', 'zh': '千'};

String _spellInt(int n, String lang) {
  if (n < 0 || n > 999999) return '$n'; // 7+ digits: leave to platform TTS
  if (n >= 1000) {
    // Thousands: assemble "<k> thousand[ rest]" per lang.
    final k = n ~/ 1000, rest = n % 1000;
    final word = _thousand[lang] ?? _thousand['en']!;
    final isCjk = lang == 'ko' || lang == 'zh';
    final sep = isCjk ? '' : ' ';
    final head = isCjk ? '${_spellInt(k, lang)}$word' : '${_spellInt(k, lang)} $word';
    if (rest == 0) return head;
    return '$head$sep${_spellInt(rest, lang)}';
  }
  if (lang == 'ko') return _spellKoZh(n, _koNum, '십', '백');
  if (lang == 'zh') return _spellKoZh(n, _zhNum, '十', '百');
  final d = (lang == 'vi') ? _viNum : _enNum;
  if (lang == 'vi') {
    if (n < 10) return d[n];
    if (n < 100) {
      final t = n ~/ 10, u = n % 10;
      final tens = t == 1 ? 'mười' : '${d[t]} mươi';
      if (u == 0) return tens;
      if (u == 5 && t >= 1) return '$tens lăm'; // 15/25/35… all "lăm"
      if (u == 1 && t > 1) return '$tens mốt';
      return '$tens ${d[u]}';
    }
    final h = n ~/ 100, rest = n % 100;
    final base = '${d[h]} trăm';
    if (rest == 0) return base;
    if (rest < 10) return '$base lẻ ${d[rest]}'; // VN: "lẻ" between hundreds and units
    return '$base ${_spellInt(rest, lang)}';
  }
  // English
  if (n < 10) return d[n];
  const teen = ['ten','eleven','twelve','thirteen','fourteen','fifteen','sixteen','seventeen','eighteen','nineteen'];
  const tens = ['','','twenty','thirty','forty','fifty','sixty','seventy','eighty','ninety'];
  if (n < 20) return teen[n - 10];
  if (n < 100) {
    final u = n % 10;
    return u == 0 ? tens[n ~/ 10] : '${tens[n ~/ 10]}-${d[u]}';
  }
  final h = n ~/ 100, rest = n % 100;
  return rest == 0 ? '${d[h]} hundred' : '${d[h]} hundred ${_spellInt(rest, lang)}';
}

// Word for "to" in ranges and "point" in decimals, per language.
const _rangeWord = {'en': ' to ', 'vi': ' đến ', 'ko': ' 부터 ', 'zh': ' 到 '};
const _pointWord = {'en': ' point ', 'vi': ' phẩy ', 'ko': ' 점 ', 'zh': ' 点 '};
const _hourWord = {'en': ' ', 'vi': ' giờ ', 'ko': ' 시 ', 'zh': '点'};
const _minWord = {'en': '', 'vi': ' phút', 'ko': ' 분', 'zh': '分'};

// KO native-counter modifier forms (1-10, 20). g2pK numerals.py + counter list.
// When a number directly precedes one of these counters, native form wins.
const _koNativeMod = {
  1: '한', 2: '두', 3: '세', 4: '네', 5: '다섯',
  6: '여섯', 7: '일곱', 8: '여덟', 9: '아홉', 10: '열', 20: '스무',
};
const _koCounters = ['개','명','시간','시','권','마리','대','벌','켤레','번',
  '살','잔','병','자루','채','척','군데','그루','모','발','쌈','정','짝','톨','통'];

// ZH measure words requiring 两 instead of 二 (convention; not in PaddleSpeech num.py).
const _zhMeasureForLiang = ['个','百','千','万','本','只','条','斤','米','公里','位','杯','碗','次','分'];

const _enOrd = {
  '1': 'first', '2': 'second', '3': 'third', '4': 'fourth', '5': 'fifth',
  '6': 'sixth', '7': 'seventh', '8': 'eighth', '9': 'ninth', '10': 'tenth',
  '11': 'eleventh', '12': 'twelfth', '13': 'thirteenth', '20': 'twentieth',
};

/// Normalize [text] for TTS in [lang]. Idempotent; pass-through for unknown.
/// Rule sourcing: NeMo TN (telephone/date/electronic/range), PaddleSpeech zh
/// frontend (num/chronology/phonecode), Coqui TTS cleaners, g2pK (KO numerals),
/// Vinorm (VI conventions). See PLANNING research note for per-rule citations.
String normalizeForTts(String text, String lang) {
  var out = text;
  // EN year-pair: 19xx/20xx → "nineteen oh nine" / "twenty twenty-six".
  // Coqui _expand_number cutoff convention. Skip *00 (let it be "two thousand").
  if (lang == 'en') {
    out = out.replaceAllMapped(RegExp(r'\b(19|20)(\d{2})\b'), (m) {
      final low = int.parse(m[2]!);
      if (low == 0) return m[0]!;
      final hi = m[1] == '19' ? 'nineteen' : 'twenty';
      return low < 10 ? '$hi oh ${_enNum[low]}' : '$hi ${_spellInt(low, 'en')}';
    });
  }
  // KO counter-bound number → native modifier. Must run BEFORE int regex.
  // \b doesn't work next to Hangul (non-ASCII), use explicit terminators.
  if (lang == 'ko') {
    final countersAlt = _koCounters.join('|');
    out = out.replaceAllMapped(RegExp(r'(\d+)\s*(' + countersAlt + r')(?=\s|$|[.,!?;])'), (m) {
      final n = int.parse(m[1]!);
      final mod = _koNativeMod[n];
      return mod == null ? m[0]! : '$mod ${m[2]}';
    });
  }
  // VND suffix: "3000đ" / "3000 VNĐ" → "<spelled> đồng".
  // \b broken for đ (non-ASCII), use explicit boundary lookahead.
  if (lang == 'vi') {
    out = out.replaceAllMapped(RegExp(r'(\d+)\s*(đ|VNĐ|VND)(?=\s|$|[.,!?;])'),
        (m) => '${m[1]} đồng');
  }
  // KRW suffix: number+원 stays literal — 원 is already correct in TTS.
  // emails (before URL + before . replacement) — NeMo electronic.py
  out = out.replaceAllMapped(RegExp(r'([\w.+-]+)@([\w-]+(?:\.[\w-]+)+)'),
      (m) => '${m[1]!.replaceAll('.', ' dot ')} at ${m[2]!.replaceAll('.', ' dot ')}');
  // URLs — http(s)://… → spelled scheme + slashes/dots
  out = out.replaceAllMapped(RegExp(r'https?://(\S+)'),
      (m) => 'h t t p s ${m[1]!.replaceAll('/', ' slash ').replaceAll('.', ' dot ')}');
  // versions v1.2.3 → "v one dot two dot three" (EN/passthrough)
  out = out.replaceAllMapped(RegExp(r'\bv(\d+(?:\.\d+){1,3})\b'),
      (m) => 'v ${m[1]!.split('.').join(' dot ')}');
  // EN ordinals 1st/2nd/3rd/…  — Coqui _expand_ordinal
  if (lang == 'en') {
    out = out.replaceAllMapped(RegExp(r'\b(\d+)(st|nd|rd|th)\b'), (m) {
      final n = m[1]!;
      return _enOrd[n] ?? '${_spellInt(int.parse(n), 'en')}th';
    });
  }
  // VI dotted-thousands "10.000" → "10000" (then spelled). VN only — EN uses
  // "." as decimal, so this would be wrong elsewhere.
  if (lang == 'vi') {
    out = out.replaceAllMapped(RegExp(r'\b(\d{1,3})(\.\d{3})+\b'),
        (m) => m[0]!.replaceAll('.', ''));
  }
  // simple fractions a/b (1-99 each) — language-aware
  out = out.replaceAllMapped(RegExp(r'\b(\d{1,2})/(\d{1,2})\b'), (m) {
    final a = int.parse(m[1]!), b = int.parse(m[2]!);
    if (lang == 'vi') return '${_spellInt(a, 'vi')} phần ${_spellInt(b, 'vi')}';
    if (lang == 'zh') return '${_spellInt(b, 'zh')}分之${_spellInt(a, 'zh')}';
    if (lang == 'ko') return '${_spellInt(b, 'ko')}분의 ${_spellInt(a, 'ko')}';
    return '${_spellInt(a, 'en')} over ${_spellInt(b, 'en')}';
  });
  // strip EN thousands grouping ("1,234" → "1234"). VN dotted-thousands already handled above.
  out = out.replaceAllMapped(RegExp(r'(\d),(\d{3})\b'), (m) => '${m[1]}${m[2]}');
  // times HH:MM (24h friendly)
  out = out.replaceAllMapped(RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b'),
      (m) => '${m[1]}${_hourWord[lang] ?? ' '}${m[2]}${_minWord[lang] ?? ''}');
  // numeric ranges 5-10 (don't eat dates: skip if surrounded by /)
  out = out.replaceAllMapped(RegExp(r'(?<![\d/])(\d{1,4})\s*-\s*(\d{1,4})(?![\d/])'),
      (m) => '${m[1]}${_rangeWord[lang] ?? ' to '}${m[2]}');
  // decimals 1.5 (keep VN "phẩy" rule)
  out = out.replaceAllMapped(RegExp(r'\b(\d+)\.(\d+)\b'),
      (m) => '${m[1]}${_pointWord[lang] ?? ' point '}${m[2]}');
  // currency before %
  _currency.forEach((sym, byLang) {
    final word = byLang[lang] ?? byLang['en'];
    if (word == null) return;
    out = out.replaceAllMapped(RegExp('\\$sym\\s*(\\d+(?:[.,]\\d+)?)'),
        (m) => '${m[1]}$word');
  });
  // percent
  out = out.replaceAllMapped(RegExp(r'(\d+(?:[.,]\d+)?)\s*%'),
      (m) => '${m[1]}${_percent[lang] ?? _percent['en']}');
  // units
  for (final m in {..._units[lang] ?? const {}, ..._units['_']!}.entries) {
    out = out.replaceAll(m.key, m.value);
  }
  // abbreviations (language-specific)
  for (final m in (_abbr[lang] ?? const <String, String>{}).entries) {
    out = out.replaceAll(m.key, m.value);
  }
  // ALL-CAPS acronyms (2-5 letters, word-boundary) → spell out letter-by-letter
  out = out.replaceAllMapped(RegExp(r'\b([A-Z]{2,5})\b'),
      (m) => m[1]!.split('').join(' '));
  // integers (0-999999) — language-aware. 7+ digits left to platform.
  out = out.replaceAllMapped(RegExp(r'\b(\d{1,6})\b'),
      (m) => _spellInt(int.parse(m[1]!), lang));
  // ZH 两 vs 二 — post-pass: 二 before measure word becomes 两.
  if (lang == 'zh') {
    final mw = _zhMeasureForLiang.join('|');
    out = out.replaceAllMapped(RegExp('二(?=$mw)'), (_) => '两');
  }
  return out;
}
