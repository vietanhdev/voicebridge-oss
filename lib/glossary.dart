import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A locked term: phrase whose translation must never drift.
class GlossaryEntry {
  final String src, dst, srcLang, dstLang;
  final bool safety;
  GlossaryEntry({required this.src, required this.dst, required this.srcLang, required this.dstLang, this.safety = false});
  Map<String, dynamic> toJson() => {'s': src, 'd': dst, 'sl': srcLang, 'dl': dstLang, 'safe': safety};
  factory GlossaryEntry.fromJson(Map<String, dynamic> j) => GlossaryEntry(
        src: j['s'] as String, dst: j['d'] as String,
        srcLang: j['sl'] as String, dstLang: j['dl'] as String, safety: (j['safe'] as bool?) ?? false);
}

/// Translation domain — swaps the bundled term pack.
enum Domain { factory, medical, construction, general }

/// Bundled packs per domain. Read-only; user-added terms persist separately.
const _packs = {
  Domain.factory: [
    ['en', 'vi', 'emergency stop', 'dừng khẩn cấp', true],
    ['en', 'vi', 'safety helmet', 'mũ bảo hộ', true],
    ['en', 'vi', 'forklift', 'xe nâng', false],
    ['en', 'vi', 'lockout-tagout', 'khóa và treo thẻ', true],
    ['en', 'vi', 'PPE', 'đồ bảo hộ cá nhân', true],
    ['ko', 'vi', '안전모', 'mũ bảo hộ', true],
    ['ko', 'vi', '비상정지', 'dừng khẩn cấp', true],
  ],
  Domain.medical: [
    ['en', 'vi', 'blood pressure', 'huyết áp', false],
    ['en', 'vi', 'allergy', 'dị ứng', true],
    ['en', 'vi', 'emergency room', 'phòng cấp cứu', true],
    ['en', 'vi', 'prescription', 'đơn thuốc', false],
    ['ko', 'vi', '응급실', 'phòng cấp cứu', true],
  ],
  Domain.construction: [
    ['en', 'vi', 'scaffold', 'giàn giáo', true],
    ['en', 'vi', 'safety harness', 'dây an toàn', true],
    ['en', 'vi', 'hard hat', 'mũ bảo hộ', true],
    ['en', 'vi', 'crane', 'cần cẩu', false],
    ['en', 'vi', 'permit to work', 'giấy phép làm việc', true],
  ],
  Domain.general: <List<Object>>[],
};

List<GlossaryEntry> _bundledFor(Domain d) => _packs[d]!.map((e) => GlossaryEntry(
      srcLang: e[0] as String, dstLang: e[1] as String,
      src: e[2] as String, dst: e[3] as String, safety: e[4] as bool)).toList();

class Glossary extends ChangeNotifier {
  final List<GlossaryEntry> entries = [];
  List<GlossaryEntry> _bundled = [];
  final List<GlossaryEntry> _user = [];
  Domain domain = Domain.factory;
  SharedPreferences? _p;

  Glossary([Domain d = Domain.factory]) { _bundled = _bundledFor(d); domain = d; _rebuild(); }

  /// Load persisted user-added entries; safe to call once at startup.
  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final raw = _p!.getString('user_glos');
    if (raw != null) {
      try {
        _user
          ..clear()
          ..addAll((json.decode(raw) as List).map((e) => GlossaryEntry.fromJson(e as Map<String, dynamic>)));
      } catch (_) {/* ignore corrupt blob */}
    }
    _rebuild();
    notifyListeners();
  }

  void _save() {
    _p?.setString('user_glos', json.encode(_user.map((e) => e.toJson()).toList()));
  }

  void _rebuild() {
    entries
      ..clear()
      ..addAll(_user) // user terms first (override priority)
      ..addAll(_bundled);
  }

  void setDomain(Domain d) {
    domain = d;
    _bundled = _bundledFor(d);
    _rebuild();
    notifyListeners();
  }

  void add(GlossaryEntry e) {
    _user.insert(0, e);
    _save();
    _rebuild();
    notifyListeners();
  }

  void removeAt(int i) {
    if (i < 0 || i >= entries.length) return;
    // Only user-added entries are removable; bundled are protected.
    if (i < _user.length) {
      _user.removeAt(i);
      _save();
    }
    _rebuild();
    notifyListeners();
  }

  /// True if the entry at [i] is user-added (vs bundled domain term).
  bool isUserAt(int i) => i >= 0 && i < _user.length;

  /// Returns (text, enforced): surface locked target term if missing from MT output.
  (String, bool) apply(String original, String translated, String srcLang, String dstLang) {
    var out = translated;
    var enforced = false;
    final lo = original.toLowerCase();
    for (final e in entries) {
      if (e.srcLang == srcLang && e.dstLang == dstLang && lo.contains(e.src.toLowerCase())) {
        if (!out.toLowerCase().contains(e.dst.toLowerCase())) {
          out = '$out  ⚑ ${e.dst}';
          enforced = true;
        }
      }
    }
    return (out, enforced);
  }
}
