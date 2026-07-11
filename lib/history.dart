import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persistent conversation history (append-only JSONL). Each line = one Turn.
class History extends ChangeNotifier {
  final List<Map<String, dynamic>> turns = [];
  File? _file;

  Future<void> load() async {
    final dir = await getApplicationDocumentsDirectory();
    _file = File('${dir.path}/voicebridge_history.jsonl');
    if (await _file!.exists()) {
      for (final ln in await _file!.readAsLines()) {
        if (ln.trim().isEmpty) continue;
        try { turns.add(json.decode(ln) as Map<String, dynamic>); } catch (_) {}
      }
    }
    notifyListeners();
  }

  Future<void> add({required String src, required String dst, required String from, required String to, required bool enforced}) async {
    final t = {'ts': DateTime.now().toIso8601String(), 'from': from, 'to': to, 'src': src, 'dst': dst, 'glossary': enforced};
    turns.insert(0, t);
    if (_file != null) await _file!.writeAsString('${json.encode(t)}\n', mode: FileMode.append);
    notifyListeners();
  }

  Future<void> clear() async {
    turns.clear();
    if (_file != null && await _file!.exists()) await _file!.delete();
    notifyListeners();
  }

  String exportText() => turns.reversed.map((t) =>
      '[${t['ts']}] ${t['from']}→${t['to']}\n  ${t['src']}\n  → ${t['dst']}${t['glossary'] == true ? '  ⚑' : ''}').join('\n\n');
}
