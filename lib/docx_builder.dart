import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Minimal on-device DOCX (OOXML) generator — no native deps, pure Dart.
/// Produces a title + a bordered 2-column table (Original | Translation).

String _esc(String s) => s
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

// size = half-points (22 → 11pt). color = RRGGBB hex.
String _para(String text, {bool bold = false, int size = 22, String color = '000000'}) {
  final rpr = '<w:rPr>${bold ? '<w:b/>' : ''}<w:sz w:val="$size"/><w:color w:val="$color"/></w:rPr>';
  return '<w:p><w:r>$rpr<w:t xml:space="preserve">${_esc(text)}</w:t></w:r></w:p>';
}

String _cell(String innerXml) =>
    '<w:tc><w:tcPr><w:tcW w:w="4600" w:type="dxa"/></w:tcPr>$innerXml</w:tc>';

/// Returns the bytes of a valid .docx file.
Uint8List buildOcrDocx({
  required String title,
  required String srcLabel,
  required String dstLabel,
  required List<({String src, String dst})> rows,
}) {
  final trs = StringBuffer()
    ..write('<w:tr>${_cell(_para(srcLabel, bold: true))}'
        '${_cell(_para(dstLabel, bold: true, color: '0B7A6B'))}</w:tr>');
  for (final r in rows) {
    trs.write('<w:tr>${_cell(_para(r.src, color: '555555'))}'
        '${_cell(_para(r.dst, bold: true))}</w:tr>');
  }

  const borders = '<w:tblBorders>'
      '<w:top w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '<w:left w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '<w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '<w:right w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '<w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '<w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '</w:tblBorders>';
  final table = '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>$borders</w:tblPr>$trs</w:tbl>';

  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>${_para(title, bold: true, size: 36)}$table${_para('')}'
      '<w:sectPr/></w:body></w:document>';

  const contentTypes = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
      '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
      '<Default Extension="xml" ContentType="application/xml"/>'
      '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
      '</Types>';
  const rels = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
      '</Relationships>';

  final ar = Archive();
  void add(String path, String content) {
    final b = utf8.encode(content);
    ar.addFile(ArchiveFile(path, b.length, b));
  }

  add('[Content_Types].xml', contentTypes);
  add('_rels/.rels', rels);
  add('word/document.xml', document);
  return Uint8List.fromList(ZipEncoder().encode(ar));
}

/// Layout-preserving DOCX: reconstruct rows/columns from block boxes so tables
/// and multi-column signs export as a real grid. cells = OCR blocks with coords.
Uint8List buildStructuredDocx({
  required String title,
  required List<({String dst, double l, double t, double r, double b})> cells,
}) {
  // Cluster into rows by vertical overlap, then sort each row left→right.
  final items = [...cells]..sort((a, c) => a.t.compareTo(c.t));
  final rows = <List<({String dst, double l, double t, double r, double b})>>[];
  for (final it in items) {
    final row = rows.isNotEmpty && (it.t - rows.last.first.t).abs() < 40 ? rows.last : (rows..add([])).last;
    row.add(it);
  }
  final maxCols = rows.fold(1, (m, r) => r.length > m ? r.length : m);
  final trs = StringBuffer();
  for (final r in rows) {
    r.sort((a, c) => a.l.compareTo(c.l));
    final cellsXml = [for (final c in r) _cell(_para(c.dst, bold: true))]
      ..addAll(List.filled(maxCols - r.length, _cell(_para(''))));
    trs.write('<w:tr>${cellsXml.join()}</w:tr>');
  }
  const borders = '<w:tblBorders><w:top w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '<w:bottom w:val="single" w:sz="4" w:color="CCCCCC"/><w:insideH w:val="single" w:sz="4" w:color="CCCCCC"/>'
      '<w:insideV w:val="single" w:sz="4" w:color="CCCCCC"/></w:tblBorders>';
  final table = '<w:tbl><w:tblPr><w:tblW w:w="0" w:type="auto"/>$borders</w:tblPr>$trs</w:tbl>';
  final document = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '<w:body>${_para(title, bold: true, size: 36)}$table<w:sectPr/></w:body></w:document>';
  const ct = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>';
  const rl = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>';
  final ar = Archive();
  void add(String p, String c) { final b = utf8.encode(c); ar.addFile(ArchiveFile(p, b.length, b)); }
  add('[Content_Types].xml', ct); add('_rels/.rels', rl); add('word/document.xml', document);
  return Uint8List.fromList(ZipEncoder().encode(ar));
}
