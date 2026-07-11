import 'dart:async';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;

import 'downloader.dart';

/// On-device Whisper STT via sherpa-onnx (Apache-2.0, ONNX Runtime) — fully
/// offline, no cloud, for the interpreter hot path. Uses the pre-exported
/// multilingual **Whisper-small int8** (KO 23.3% / ZH 21.9% / EN 16.6% WER on
/// FLEURS, see benchmarks/asr/) which is far stronger than the platform
/// recognizer for Korean. Models (~375 MB) download once from Hugging Face on
/// first use and are cached under the app support dir.
///
/// Vietnamese is NOT routed here — it keeps its PhoWhisper specialist path /
/// platform STT; this engine serves the multilingual KO/ZH/EN slot.
///
/// ## Threading
/// The sherpa decode is a synchronous FFI call: for a few-second utterance it is
/// sub-second on the 8 Elite, but run on the root isolate it would briefly block
/// the UI. The recognizer therefore lives in a **dedicated worker isolate**
/// (spawned on first use, kept warm). The main isolate only resolves the model
/// file paths (path_provider needs the platform method channel, which a plain
/// background isolate lacks) and ships them to the worker. If the isolate fails
/// to spawn for any reason, we fall back to a synchronous in-process decode so
/// on-device STT never regresses to unavailable.
class WhisperStt {
  static const repo = 'csukuangfj/sherpa-onnx-whisper-small';
  static const _baseUrl = 'https://huggingface.co/$repo/resolve/main';

  /// file name -> approx MB (for the UI size hint). Sum ≈ 375 MB.
  static const files = <String, int>{
    'small-encoder.int8.onnx': 112,
    'small-decoder.int8.onnx': 262,
    'small-tokens.txt': 1,
  };
  static int get totalMb => files.values.fold(0, (a, b) => a + b);

  /// Whisper supports these on-device here. (VN stays on PhoWhisper/platform.)
  static const supportedLangs = {'ko', 'zh', 'en'};
  static bool handles(String lang) => supportedLangs.contains(lang);

  final ModelDownload download = ModelDownload(); // exposes progress to the UI

  // --- worker-isolate plumbing (main side) ---
  Isolate? _iso;
  SendPort? _toWorker; // null until the handshake completes
  ReceivePort? _fromWorker;
  Completer<SendPort?>? _spawning; // in-flight spawn; coalesces concurrent calls
  Completer<SendPort>? _handshake; // resolved when the worker sends its inbox port
  bool _spawnFailed = false; // permanent fallback to the sync path
  final Map<int, Completer<String>> _pending = {};
  int _nextId = 0;

  // Synchronous fallback engine (only built if the isolate can't spawn).
  _WhisperEngine? _fallback;

  Future<Directory> _dir() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}/whisper-small');
    if (!await d.exists()) await d.create(recursive: true);
    return d;
  }

  /// True when all model files are present on disk.
  Future<bool> isDownloaded() async {
    final d = await _dir();
    for (final f in files.keys) {
      if (!await File('${d.path}/$f').exists()) return false;
    }
    return true;
  }

  /// Download any missing model files (idempotent). Writes to a `.part` file
  /// then renames, so an interrupted download is never mistaken for complete.
  /// Returns true once every file is present. [download] streams progress.
  Future<bool> ensureDownloaded() async {
    final d = await _dir();
    for (final entry in files.entries) {
      final dest = File('${d.path}/${entry.key}');
      if (await dest.exists()) continue;
      final part = File('${dest.path}.part');
      final ok = await download.fetch(Uri.parse('$_baseUrl/${entry.key}'), part);
      if (ok == null) return false;
      await part.rename(dest.path);
    }
    return true;
  }

  /// Spawn (once) the worker isolate and complete the handshake. Returns the
  /// worker's [SendPort], or null if spawning failed (caller uses the sync path).
  Future<SendPort?> _worker() async {
    if (_toWorker != null) return _toWorker;
    if (_spawnFailed) return null;
    if (_spawning != null) return _spawning!.future;
    final spawning = Completer<SendPort?>();
    _spawning = spawning;
    try {
      _fromWorker = ReceivePort()..listen(_onWorkerMessage);
      _handshake = Completer<SendPort>();
      _iso = await Isolate.spawn(_whisperIsolateMain, _fromWorker!.sendPort);
      _toWorker = await _handshake!.future.timeout(const Duration(seconds: 10));
      spawning.complete(_toWorker);
    } catch (e) {
      debugPrint('[VB-Whisper] isolate spawn failed, using sync path: $e');
      _spawnFailed = true;
      _fromWorker?.close();
      _fromWorker = null;
      spawning.complete(null);
    } finally {
      _spawning = null;
    }
    return spawning.future;
  }

  void _onWorkerMessage(dynamic msg) {
    if (msg is SendPort) {
      _handshake?.complete(msg);
      _handshake = null;
      return;
    }
    final m = msg as Map;
    final id = m['id'] as int;
    final c = _pending.remove(id);
    if (c == null || c.isCompleted) return;
    // On a worker-side error we return '' so the caller falls back to the
    // platform recognizer rather than surfacing a failure.
    c.complete(m['text'] as String? ?? '');
    if (m['error'] != null) debugPrint('[VB-Whisper] worker decode error: ${m['error']}');
  }

  /// Transcribe a recorded mono WAV. [lang] is the Whisper code (ko/zh/en).
  /// Returns '' on any failure (caller falls back to the platform recognizer).
  Future<String> transcribeWav(String wavPath, String lang) async {
    try {
      if (!await isDownloaded()) return '';
      final d = await _dir();
      final req = <String, dynamic>{
        'wav': wavPath,
        'lang': lang,
        'encoder': '${d.path}/small-encoder.int8.onnx',
        'decoder': '${d.path}/small-decoder.int8.onnx',
        'tokens': '${d.path}/small-tokens.txt',
        'numThreads': 2,
      };
      final sp = await _worker();
      if (sp == null) {
        // Synchronous fallback (briefly blocks this isolate; rare path).
        return (_fallback ??= _WhisperEngine()).decode(req);
      }
      final id = _nextId++;
      final c = Completer<String>();
      _pending[id] = c;
      sp.send({'id': id, ...req});
      return await c.future.timeout(const Duration(seconds: 30), onTimeout: () {
        _pending.remove(id);
        debugPrint('[VB-Whisper] decode timed out');
        return '';
      });
    } catch (e) {
      debugPrint('[VB-Whisper] transcribe failed: $e');
      return '';
    }
  }

  void dispose() {
    _toWorker?.send('dispose');
    _iso?.kill(priority: Isolate.immediate);
    _fromWorker?.close();
    _iso = null;
    _toWorker = null;
    _fromWorker = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.complete('');
    }
    _pending.clear();
    _fallback?.dispose();
    _fallback = null;
  }
}

/// Owns one sherpa [sherpa.OfflineRecognizer] and decodes WAVs. Used both inside
/// the worker isolate and (rarely) on the main isolate as the sync fallback. The
/// recognizer is rebuilt only when the language or model path changes, so a warm
/// engine decodes back-to-back utterances without reloading the ~375 MB model.
class _WhisperEngine {
  sherpa.OfflineRecognizer? _rec;
  String _key = '';

  String decode(Map req) {
    sherpa.initBindings();
    final key = '${req['lang']}|${req['encoder']}';
    if (_rec == null || _key != key) {
      _rec?.free();
      _rec = sherpa.OfflineRecognizer(sherpa.OfflineRecognizerConfig(
        model: sherpa.OfflineModelConfig(
          whisper: sherpa.OfflineWhisperModelConfig(
            encoder: req['encoder'] as String,
            decoder: req['decoder'] as String,
            language: req['lang'] as String,
            task: 'transcribe',
          ),
          tokens: req['tokens'] as String,
          numThreads: req['numThreads'] as int,
          debug: false,
          provider: 'cpu',
        ),
      ));
      _key = key;
    }
    final wave = sherpa.readWave(req['wav'] as String);
    if (wave.samples.isEmpty) return '';
    final stream = _rec!.createStream();
    stream.acceptWaveform(samples: wave.samples, sampleRate: wave.sampleRate);
    _rec!.decode(stream);
    final text = _rec!.getResult(stream).text;
    stream.free();
    return text.trim();
  }

  void dispose() {
    _rec?.free();
    _rec = null;
  }
}

/// Worker-isolate entry point. Owns a warm [_WhisperEngine] and answers decode
/// requests `{id, wav, lang, encoder, decoder, tokens, numThreads}` with
/// `{id, text}` (or `{id, text:'', error}` on failure). `'dispose'` tears down.
void _whisperIsolateMain(SendPort toMain) {
  final port = ReceivePort();
  toMain.send(port.sendPort); // handshake: hand the main isolate our inbox
  final engine = _WhisperEngine();
  port.listen((msg) {
    if (msg == 'dispose') {
      engine.dispose();
      port.close();
      Isolate.exit();
    }
    final m = msg as Map;
    final id = m['id'] as int;
    try {
      toMain.send({'id': id, 'text': engine.decode(m)});
    } catch (e) {
      toMain.send({'id': id, 'text': '', 'error': '$e'});
    }
  });
}
