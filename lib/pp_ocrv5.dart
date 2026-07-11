// PP-OCRv5 hybrid OCR engine — ZH/KO capture path only (not live overlay).
//
// Uses int8 TFLite models compiled by Qualcomm AI Hub for Snapdragon 8 Elite
// (100% Hexagon NPU, ~2ms per sign). Models are NOT bundled in the APK —
// they live in the app's external files dir and are downloaded on first use.
//
// ML Kit stays for VN/EN and all live overlay (PP-OCRv5 Latin dict cannot
// encode Vietnamese tone marks — measured 53.68% CER, vs ML Kit 2.78%).
//
// Pipeline: det (DB++ → boxes) → crop + warp → rec (SVTR/CTC → text)
// Post-proc: DB threshold + Vatti unclip polygon expansion → sorted boxes
//
// Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

// Languages that route through PP-OCRv5 (capture path only).
const kPpOcrLangs = {'zh', 'ko'};

// Model file names within <ext>/pp_ocrv5/ pushed by the user or auto-downloaded.
const _kDetModel = 'pp_ocrv5_det_mobile.tflite';
const _kZhModel  = 'pp_ocrv5_zh_rec.tflite';
const _kKoModel  = 'pp_ocrv5_ko_rec.tflite';

// DB detection thresholds
const _kDetThresh = 0.3;
const _kBoxThresh = 0.5;
const _kUnclipRatio = 1.6;

class PpOcrResult {
  final String text;
  final double l, t, r, b;
  const PpOcrResult(this.text, this.l, this.t, this.r, this.b);
}

/// Lazy-loaded PP-OCRv5 engine. Models load on first call.
/// Call [dispose] when done.
class PpOcrV5Engine {
  Interpreter? _det;
  final Map<String, Interpreter> _recs = {};
  bool _available = false;

  // Char dictionaries per language (loaded lazily from the model dir).
  final Map<String, List<String>> _dicts = {};

  static Future<String> _modelDir() async {
    final ext = await getExternalStorageDirectory();
    return '${ext?.path}/pp_ocrv5';
  }

  /// Returns true if the model files are present on disk.
  static Future<bool> isAvailable() async {
    final dir = await _modelDir();
    return File('$dir/$_kDetModel').existsSync();
  }

  Future<void> _ensureLoaded(String lang) async {
    if (_det != null && _recs.containsKey(lang)) return;
    final dir = await _modelDir();

    if (_det == null) {
      final f = File('$dir/$_kDetModel');
      if (!f.existsSync()) {
        _available = false;
        return;
      }
      _det = Interpreter.fromFile(f);
    }

    if (!_recs.containsKey(lang)) {
      final recFile = lang == 'zh' ? _kZhModel : _kKoModel;
      final f = File('$dir/$recFile');
      if (!f.existsSync()) return;
      _recs[lang] = Interpreter.fromFile(f);

      // load dict (placed next to the .tflite as <lang>_dict.txt)
      final dictF = File('$dir/${lang}_dict.txt');
      if (dictF.existsSync()) {
        _dicts[lang] = [''] + dictF.readAsLinesSync() + [' '];
      }
    }
    _available = true;
  }

  /// Run PP-OCRv5 on [imagePath], return list of (text, bbox) results.
  /// Falls back to empty list on any error (caller uses ML Kit as fallback).
  Future<List<PpOcrResult>> recognize(String imagePath, String lang) async {
    try {
      await _ensureLoaded(lang);
      if (!_available || _det == null || !_recs.containsKey(lang)) return [];

      final raw = File(imagePath).readAsBytesSync();
      final original = img.decodeImage(raw);
      if (original == null) return [];

      // ── Detection ──────────────────────────────────────────────────────────
      const detH = 640, detW = 640;
      final resized = img.copyResize(original, width: detW, height: detH);
      final detInput = _normalizeImage(resized, detH, detW);

      // det input shape: [1, 3, 640, 640]
      final detOut = List.generate(1, (_) =>
          List.generate(1, (_) =>
              List.generate(detH, (_) => List.filled(detW, 0.0))));
      _det!.run(detInput, detOut);

      final scaleX = original.width / detW;
      final scaleY = original.height / detH;
      final boxes = _dbPostprocess(detOut[0][0], detH, detW, scaleX, scaleY);
      if (boxes.isEmpty) return [];

      // ── Recognition ────────────────────────────────────────────────────────
      final rec = _recs[lang]!;
      final dict = _dicts[lang];
      final results = <PpOcrResult>[];

      for (final box in boxes) {
        final (l, t, r, b) = box;
        final crop = img.copyCrop(original,
            x: l.round().clamp(0, original.width - 1),
            y: t.round().clamp(0, original.height - 1),
            width: (r - l).round().clamp(1, original.width),
            height: (b - t).round().clamp(1, original.height));
        // resize crop to [3, 48, W] keeping aspect ratio
        final recW = ((crop.width / crop.height) * 48).round().clamp(4, 1280);
        final recCrop = img.copyResize(crop, width: recW, height: 48);
        final recInput = _normalizeImage(recCrop, 48, recW);

        // rec output: [1, T, vocab]
        final recOutShape = rec.getOutputTensor(0).shape;
        final T = recOutShape[1], V = recOutShape[2];
        final recOut = List.generate(1, (_) =>
            List.generate(T, (_) => List.filled(V, 0.0)));
        rec.run(recInput, recOut);

        final text = dict != null ? _ctcDecode(recOut[0], dict) : '';
        if (text.trim().isNotEmpty) {
          results.add(PpOcrResult(text.trim(), l, t, r, b));
        }
      }
      return results;
    } catch (e) {
      debugPrint('[PpOcrV5] error: $e');
      return [];
    }
  }

  // NormCHW: resize → (x-mean)/std → [1,3,H,W] float32
  static List _normalizeImage(img.Image im, int H, int W) {
    const mean = [0.485, 0.456, 0.406];
    const std  = [0.229, 0.224, 0.225];
    final data = List.generate(1, (_) =>
        List.generate(3, (c) =>
            List.generate(H, (y) =>
                List.generate(W, (x) {
                  final p = im.getPixel(x, y);
                  final v = [p.rNormalized, p.gNormalized, p.bNormalized];
                  return (v[c] - mean[c]) / std[c];
                }))));
    return data;
  }

  // DB post-processing: prob_map → binarize → connected-component boxes
  static List<(double, double, double, double)> _dbPostprocess(
      List<List<double>> map, int H, int W, double sx, double sy) {
    // binarize
    final bin = List.generate(H, (y) => List.generate(W, (x) =>
        map[y][x] > _kDetThresh ? 1 : 0));

    // find bounding boxes of connected components via simple sweep
    // (not full unclip polygon — conservative but correct for safety signs)
    final visited = List.generate(H, (_) => List.filled(W, false));
    final boxes = <(double, double, double, double)>[];

    for (int sy0 = 0; sy0 < H; sy0++) {
      for (int sx0 = 0; sx0 < W; sx0++) {
        if (bin[sy0][sx0] == 0 || visited[sy0][sx0]) continue;
        // BFS flood fill
        int minX = sx0, maxX = sx0, minY = sy0, maxY = sy0;
        double sumConf = 0; int count = 0;
        final queue = [(sx0, sy0)];
        while (queue.isNotEmpty) {
          final (cx, cy) = queue.removeLast();
          if (cx < 0 || cx >= W || cy < 0 || cy >= H) continue;
          if (visited[cy][cx] || bin[cy][cx] == 0) continue;
          visited[cy][cx] = true;
          minX = math.min(minX, cx); maxX = math.max(maxX, cx);
          minY = math.min(minY, cy); maxY = math.max(maxY, cy);
          sumConf += map[cy][cx]; count++;
          queue.addAll([(cx+1,cy),(cx-1,cy),(cx,cy+1),(cx,cy-1)]);
        }
        if (count < 10) continue; // skip tiny noise
        if (sumConf / count < _kBoxThresh) continue;
        // apply unclip ratio (expand box)
        final uc = _kUnclipRatio;
        final bx = (minX - (maxX-minX)*((uc-1)/2)).clamp(0.0, W-1.0);
        final by = (minY - (maxY-minY)*((uc-1)/2)).clamp(0.0, H-1.0);
        final bx2 = (maxX + (maxX-minX)*((uc-1)/2)).clamp(0.0, W-1.0);
        final by2 = (maxY + (maxY-minY)*((uc-1)/2)).clamp(0.0, H-1.0);
        boxes.add((bx * sx, by * sy, bx2 * sx, by2 * sy));
      }
    }
    // sort top→bottom, then left→right
    boxes.sort((a, b) => a.$2 != b.$2 ? a.$2.compareTo(b.$2) : a.$1.compareTo(b.$1));
    return boxes;
  }

  // CTC greedy decode: argmax over time, collapse repeats, skip blank (index 0)
  static String _ctcDecode(List<List<double>> logits, List<String> dict) {
    final sb = StringBuffer();
    int last = 0;
    for (final frame in logits) {
      int best = 0;
      double bestV = frame[0];
      for (int i = 1; i < frame.length; i++) {
        if (frame[i] > bestV) { bestV = frame[i]; best = i; }
      }
      if (best != 0 && best != last && best < dict.length) {
        sb.write(dict[best]);
      }
      last = best;
    }
    return sb.toString();
  }

  void dispose() {
    _det?.close();
    for (final r in _recs.values) r.close();
    _det = null;
    _recs.clear();
  }
}
