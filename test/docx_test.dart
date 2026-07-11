import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:voicebridge/docx_builder.dart';

void main() {
  test('buildOcrDocx produces a valid docx zip with a table and UTF-8 text', () {
    final bytes = buildOcrDocx(
      title: 'VoiceBridge OCR',
      srcLabel: 'English',
      dstLabel: 'Vietnamese',
      rows: const [(src: 'EMERGENCY STOP', dst: 'dừng khẩn cấp')],
    );
    expect(bytes.length, greaterThan(300));
    final ar = ZipDecoder().decodeBytes(bytes);
    final names = ar.files.map((f) => f.name).toSet();
    expect(names.containsAll({'[Content_Types].xml', '_rels/.rels', 'word/document.xml'}), isTrue);
    final doc = utf8.decode(
        ar.files.firstWhere((f) => f.name == 'word/document.xml').content as List<int>);
    expect(doc.contains('<w:tbl>'), isTrue); // has a table
    expect(doc.contains('dừng khẩn cấp'), isTrue); // VN text preserved
  });
}

