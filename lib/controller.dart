import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'glossary.dart';
import 'history.dart';
import 'languages.dart';
import 'pp_ocrv5.dart';
import 'pronunciation.dart';
import 'settings.dart';
import 'tts_normalize.dart';
import 'whisper_stt.dart';

enum Side { top, bottom }

enum PipeStatus { idle, listening, translating, speaking, downloading, error }

/// One translated exchange.
class Turn {
  final Side speaker;
  final Lang from;
  final Lang to;
  final String original;
  final String translated;
  final bool enforced; // a glossary term was force-surfaced
  Turn(this.speaker, this.from, this.to, this.original, this.translated, this.enforced);
}

/// Orchestrates the offline hot path: speech_to_text -> ML Kit translate -> flutter_tts.
/// Tier discipline: no network, no LLM in this path.
class InterpreterController extends ChangeNotifier {
  final Glossary glossary;
  final Pronunciation pron;
  final AppSettings settings;
  final History history;
  InterpreterController(this.glossary, this.pron, this.settings, this.history) {
    continuous = settings.continuousDefault;
  }

  final SpeechToText _stt = SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final OnDeviceTranslatorModelManager _models = OnDeviceTranslatorModelManager();

  // On-device Whisper STT (sherpa-onnx) for KO/ZH/EN — far better Korean than
  // the platform recognizer. Active only when the model is downloaded AND the
  // user has on-device STT enabled. Vietnamese keeps PhoWhisper/platform.
  final WhisperStt whisper = WhisperStt();
  final AudioRecorder _mic = AudioRecorder();
  StreamSubscription<Amplitude>? _ampSub;
  bool whisperReady = false; // model files present on disk
  bool _whisperTurn = false; // current listen turn is recording for Whisper
  bool _heardVoice = false;  // VAD detected speech this turn (Whisper has no partials)
  DateTime _whisperListenStart = DateTime.now(); // safety cap for the recording turn
  static const int _whisperMaxListenMs = 30000; // hard cap (no platform listenFor here)
  String? _wavPath;

  /// Re-check whether the Whisper model is on disk (call after init/download).
  Future<void> refreshWhisper() async {
    whisperReady = await whisper.isDownloaded();
    debugPrint('[VB-Whisper] model downloaded=$whisperReady (on-device STT for KO/ZH/EN)');
    notifyListeners();
  }

  /// Use on-device Whisper for this side when enabled, supported (KO/ZH/EN),
  /// and the model is present. VN never routes here.
  bool _useWhisper(Side side) =>
      settings.useOnDeviceStt && whisperReady && WhisperStt.handles(langOf(side).code);

  // PP-OCRv5 TFLite engine for ZH/KO capture (NPU-accelerated, ~2ms/sign).
  // Null when models aren't present on device — ocrTranslate falls back to ML Kit.
  final PpOcrV5Engine _ppOcr = PpOcrV5Engine();

  Lang top = langByCode('ko');
  Lang bottom = langByCode('vi');

  PipeStatus status = PipeStatus.idle;
  Side? activeSide;
  String partial = '';
  String statusMsg = '';
  bool sttAvailable = false;
  bool continuous = false; // hands-free: auto-restart listening after each turn
  final List<Turn> turns = [];

  Lang langOf(Side s) => s == Side.top ? top : bottom;
  Lang otherOf(Side s) => s == Side.top ? bottom : top;

  Future<void> init() async {
    final micStatus = await Permission.microphone.request();
    debugPrint('[VB] mic permission: $micStatus');
    try {
      sttAvailable = await _stt.initialize(
        onStatus: (s) {
          debugPrint('[VB] STT status: $s');
          _onSttStatus(s);
        },
        onError: (e) {
          debugPrint('[VB] STT error: ${e.errorMsg} permanent=${e.permanent}');
          statusMsg = e.errorMsg.contains('no_match')
              ? "Didn't catch that — tap and speak again"
              : 'Mic: ${e.errorMsg}';
          if (status == PipeStatus.listening) _reset();
          notifyListeners();
        },
        debugLogging: true,
      );
    } catch (e) {
      sttAvailable = false;
      statusMsg = 'STT init failed: $e';
    }
    debugPrint('[VB] STT initialize -> available=$sttAvailable msg="$statusMsg"');
    if (sttAvailable) {
      final locales = await _stt.locales();
      debugPrint('[VB] STT locales: ${locales.length} '
          '(has ko=${locales.any((l) => l.localeId.startsWith("ko"))} '
          'vi=${locales.any((l) => l.localeId.startsWith("vi"))})');
    }
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(settings.ttsRate);
    await refreshWhisper(); // is the on-device Whisper model already downloaded?
    await ensureModels();
    notifyListeners();
  }

  void _onSttStatus(String s) {
    if ((s == 'done' || s == 'notListening') && status == PipeStatus.listening) {
      // listening ended without a final result -> go idle
      if (activeSide != null && partial.trim().isEmpty) _reset();
    }
  }

  Future<void> ensureModels() async {
    if (_ensuring) return; // serialize: rapid switches must not overlap downloads
    _ensuring = true;
    status = PipeStatus.downloading;
    notifyListeners();
    for (final l in {top, bottom}) {
      try {
        final downloaded = await _models.isModelDownloaded(l.mlkit.bcpCode);
        if (!downloaded) {
          statusMsg = 'Downloading ${l.name} model…';
          notifyListeners();
          await _models.downloadModel(l.mlkit.bcpCode, isWifiRequired: false);
        }
      } catch (e) {
        statusMsg = 'Model error: $e';
      }
    }
    statusMsg = '';
    status = PipeStatus.idle;
    _ensuring = false;
    notifyListeners();
  }

  void setLang(Side side, Lang lang) {
    if (status == PipeStatus.listening) { _stt.cancel(); _cancelWhisperCapture(); } // don't switch mid-listen
    continuous = false;
    if (side == Side.top) {
      top = lang;
    } else {
      bottom = lang;
    }
    _reset();
    notifyListeners();
    ensureModels();
  }

  bool _ensuring = false;

  void swap() {
    final t = top;
    top = bottom;
    bottom = t;
    notifyListeners();
  }

  void toggleContinuous() {
    continuous = !continuous;
    notifyListeners();
  }

  Future<void> listen(Side side) async {
    debugPrint('[VB] listen(side=$side) sttAvailable=$sttAvailable status=$status');
    if (status == PipeStatus.listening) {
      await stop();
      return;
    }
    if (_useWhisper(side)) {
      await _listenWhisper(side);
      return;
    }
    if (!sttAvailable) {
      sttAvailable = await _stt.initialize(onStatus: _onSttStatus, debugLogging: true);
      debugPrint('[VB] re-init STT -> $sttAvailable');
    }
    if (!sttAvailable) {
      statusMsg = 'Speech recognition unavailable on this device';
      status = PipeStatus.error;
      notifyListeners();
      return;
    }
    if (status == PipeStatus.listening) {
      await stop();
      return;
    }
    await _tts.stop();
    activeSide = side;
    partial = '';
    status = PipeStatus.listening;
    statusMsg = '';
    _noiseFloor = 0;
    _speaking = false;
    _lastVoice = DateTime.now();
    _startVoice = DateTime.now();
    notifyListeners();

    await _stt.listen(
      onResult: _onResult,
      onSoundLevelChange: _onLevel,
      listenOptions: SpeechListenOptions(
        localeId: langOf(side).sttLocale,
        partialResults: true,
        listenMode: ListenMode.dictation,
        cancelOnError: false, // noise spikes shouldn't kill the session
        autoPunctuation: true,
        // We own endpointing (noise-robust VAD); keep platform cutoffs long.
        pauseFor: const Duration(seconds: 30),
        listenFor: const Duration(seconds: 120),
      ),
    );
  }

  /// On-device Whisper listen turn: record mic → energy-VAD endpoint → transcribe.
  /// We capture a 16 kHz mono WAV (`sherpa.readWave` reads it directly) and reuse
  /// the same hysteresis VAD as the platform path, but endpoint on "heard voice
  /// then silence" since Whisper produces no streaming partials.
  Future<void> _listenWhisper(Side side) async {
    if (!await _mic.hasPermission()) {
      statusMsg = 'Microphone permission required';
      status = PipeStatus.error;
      notifyListeners();
      return;
    }
    await _tts.stop();
    activeSide = side;
    partial = '';
    status = PipeStatus.listening;
    statusMsg = '';
    _noiseFloor = 0;
    _speaking = false;
    _heardVoice = false;
    _whisperTurn = true;
    _lastVoice = DateTime.now();
    _startVoice = DateTime.now();
    _whisperListenStart = DateTime.now();
    notifyListeners();

    final tmp = await getTemporaryDirectory();
    _wavPath = '${tmp.path}/vb_stt.wav';
    await _mic.start(
      const RecordConfig(encoder: AudioEncoder.wav, sampleRate: 16000, numChannels: 1),
      path: _wavPath!,
    );
    // Amplitude.current is dBFS (≤0); the VAD hysteresis works the same as the
    // platform sound-level (louder = higher value).
    _ampSub?.cancel();
    _ampSub = _mic.onAmplitudeChanged(const Duration(milliseconds: 150))
        .listen((a) => _onLevelWhisper(a.current));
  }

  void _onLevelWhisper(double db) {
    final margin = settings.vadEnterMarginDb;
    final enter = _noiseFloor + margin, exit = _noiseFloor + margin / 2;
    if (db > (_speaking ? exit : enter)) {
      if (!_speaking) { _speaking = true; _startVoice = DateTime.now(); }
      _heardVoice = true;
      _lastVoice = DateTime.now();
    } else {
      _noiseFloor = _noiseFloor == 0 ? db : _noiseFloor * 0.97 + db * 0.03;
      if (DateTime.now().difference(_lastVoice).inMilliseconds > 500) _speaking = false;
    }
    final spokeEnough = DateTime.now().difference(_startVoice).inMilliseconds > 300;
    final hungOver = DateTime.now().difference(_lastVoice).inMilliseconds > settings.vadHangoverMs;
    // Safety cap: end the turn after the max duration even if VAD never fired (mic
    // tapped but nobody spoke, or non-stop noise) — otherwise recording runs forever
    // since the Whisper path has no platform listenFor. transcribes if voice was heard.
    final tooLong = DateTime.now().difference(_whisperListenStart).inMilliseconds > _whisperMaxListenMs;
    if (status == PipeStatus.listening && ((_heardVoice && spokeEnough && hungOver) || tooLong)) {
      _endTurnWhisper();
    }
  }

  bool _transcribing = false;
  Future<void> _endTurnWhisper() async {
    if (status != PipeStatus.listening || _transcribing) return;
    _transcribing = true;
    final side = activeSide;
    await _ampSub?.cancel();
    _ampSub = null;
    final path = await _mic.stop(); // flushes the WAV
    _whisperTurn = false;
    final lang = side != null ? langOf(side).code : '';
    if (side == null || path == null || !_heardVoice) {
      _transcribing = false;
      _reset();
      notifyListeners();
      return;
    }
    status = PipeStatus.translating;
    statusMsg = 'Transcribing…';
    notifyListeners();
    final text = await whisper.transcribeWav(path, lang);
    _transcribing = false;
    debugPrint('[VB-Whisper] ($lang) "$text"');
    if (text.isEmpty) {
      _reset();
      notifyListeners();
      return;
    }
    _process(side, text);
  }

  // Adaptive energy VAD with hysteresis (Silero-style endpointing, ONNX-free):
  // enter speech at floor+margin, hold while floor+margin/2, end after hangover. The
  // enter margin is user-tunable (mic sensitivity): low gate catches quiet speech but
  // is more triggerable by background talk. Floor tracks ambient only when no voice, so
  // factory noise raises the bar, not cuts. Quiet speech that never crossed the old
  // fixed 6dB gate used to end the turn early (stale _lastVoice) — the gate now drops.
  double _noiseFloor = 0;
  bool _speaking = false;
  DateTime _lastVoice = DateTime.now();
  DateTime _startVoice = DateTime.now();
  void _onLevel(double db) {
    final margin = settings.vadEnterMarginDb; // 9dB (loud-only) … 3dB (whispers)
    final enter = _noiseFloor + margin, exit = _noiseFloor + margin / 2;
    if (db > (_speaking ? exit : enter)) {
      if (!_speaking) { _speaking = true; _startVoice = DateTime.now(); }
      _lastVoice = DateTime.now();
    } else {
      _noiseFloor = _noiseFloor == 0 ? db : _noiseFloor * 0.97 + db * 0.03; // ambient only
      if (DateTime.now().difference(_lastVoice).inMilliseconds > 500) _speaking = false;
    }
    final spokeEnough = DateTime.now().difference(_startVoice).inMilliseconds > 300;
    if (status == PipeStatus.listening && partial.trim().isNotEmpty && spokeEnough &&
        DateTime.now().difference(_lastVoice).inMilliseconds > settings.vadHangoverMs) {
      _endTurn(); // hangover elapsed -> finalize, preserves hands-free
    }
  }

  // Finalize captured speech but keep continuous mode (vs tap-stop which ends it).
  Future<void> _endTurn() async {
    if (status != PipeStatus.listening) return;
    final captured = partial.trim();
    final side = activeSide;
    await _stt.cancel();
    if (side != null && captured.isNotEmpty) {
      _process(side, captured);
    } else {
      _reset();
      notifyListeners();
    }
  }

  /// Stop + discard an in-flight Whisper recording without transcribing.
  Future<void> _cancelWhisperCapture() async {
    await _ampSub?.cancel();
    _ampSub = null;
    if (_whisperTurn) {
      try { await _mic.stop(); } catch (_) {}
      _whisperTurn = false;
    }
  }

  Future<void> stop() async {
    if (status != PipeStatus.listening) return;
    continuous = false; // tapping stop ends the hands-free loop
    // Whisper turn: stop recording and transcribe what we captured so far.
    if (_whisperTurn) {
      await _endTurnWhisper();
      return;
    }
    // Process whatever was recorded so far instead of discarding it.
    final captured = partial.trim();
    final side = activeSide;
    await _stt.cancel(); // cancel to avoid a late duplicate final result
    if (side != null && captured.isNotEmpty) {
      _process(side, captured);
    } else {
      _reset();
      notifyListeners();
    }
  }

  void _onResult(SpeechRecognitionResult r) {
    debugPrint('[VB] result "${r.recognizedWords}" final=${r.finalResult}');
    partial = r.recognizedWords;
    notifyListeners();
    if (r.finalResult && r.recognizedWords.trim().isNotEmpty) {
      _process(activeSide!, r.recognizedWords.trim());
    }
  }

  Future<void> _process(Side side, String text) async {
    final from = langOf(side);
    final to = otherOf(side);
    status = PipeStatus.translating;
    notifyListeners();

    String translated = text;
    try {
      translated = await _translate(from, to, text);
      debugPrint('[VB] translate "$text" ${from.code}->${to.code} = "$translated"');
    } catch (e) {
      statusMsg = 'Translate error: $e';
      debugPrint('[VB] translate ERROR: $e');
    }

    final (finalText, enforced) = glossary.apply(text, translated, from.code, to.code);
    turns.insert(0, Turn(side, from, to, text, finalText, enforced));
    history.add(src: text, dst: finalText, from: from.code, to: to.code, enforced: enforced);
    partial = '';

    status = PipeStatus.speaking;
    notifyListeners();
    try {
      // TTS frontend: pronunciation respelling → text normalization (numbers,
      // %, currency, units, abbreviations, acronyms) → speak.
      final toSpeak = normalizeForTts(pron.apply(finalText.replaceAll('⚑', ''), to.code), to.code);
      await _tts.setLanguage(to.ttsLocale);
      final spoken = await _tts.speak(toSpeak);
      debugPrint('[VB] tts speak(${to.ttsLocale}) "$toSpeak" -> $spoken');
    } catch (e) {
      debugPrint('[VB] tts ERROR: $e');
    }

    _reset();
    notifyListeners();

    // Hands-free: after TTS completes, auto-resume listening on the same side.
    // (Half-duplex: restart only after playback to avoid transcribing our own TTS.)
    if (continuous) {
      final next = side == Side.top ? Side.bottom : Side.top; // hand mic to the other speaker
      Future.delayed(const Duration(milliseconds: 350), () {
        if (continuous && status == PipeStatus.idle) listen(next);
      });
    }
  }

  /// Translate with self-heal: if the model isn't actually present yet the
  /// native side throws NullPointerException — force-download both, retry once.
  Future<String> _translate(Lang from, Lang to, String text) async {
    try {
      final tr = OnDeviceTranslator(sourceLanguage: from.mlkit, targetLanguage: to.mlkit);
      final r = await tr.translateText(text);
      await tr.close();
      return r;
    } catch (_) {
      for (final l in [from, to]) {
        await _models.downloadModel(l.mlkit.bcpCode, isWifiRequired: false);
      }
      final tr = OnDeviceTranslator(sourceLanguage: from.mlkit, targetLanguage: to.mlkit);
      final r = await tr.translateText(text);
      await tr.close();
      return r;
    }
  }

  void _reset() {
    status = PipeStatus.idle;
    activeSide = null;
    _whisperTurn = false;
    _heardVoice = false;
  }

  /// Latest text to show in [side]'s own language, from the most recent turn.
  ({String text, String caption, bool enforced})? panelContent(Side side) {
    if (turns.isEmpty) return null;
    final t = turns.first;
    final lang = langOf(side);
    if (t.to.code == lang.code) {
      return (text: t.translated, caption: t.original, enforced: t.enforced);
    }
    if (t.from.code == lang.code) {
      return (text: t.original, caption: t.translated, enforced: false);
    }
    return null;
  }

  /// On-device model self-test with example data (MT for all pairs + TTS voices).
  /// Trigger: long-press the VoiceBridge wordmark. Results go to logcat ([VB-TEST]).
  Future<void> selfTest() async {
    debugPrint('[VB-TEST] ===== self-test start =====');
    statusMsg = 'Running on-device self-test…';
    status = PipeStatus.downloading;
    notifyListeners();

    const samples = [
      ['en', 'vi', 'Please wear your safety helmet before entering the line.'],
      ['vi', 'en', 'Cẩn thận, sàn nhà đang trơn trượt.'],
      ['en', 'ko', 'Where is the emergency exit?'],
      ['ko', 'vi', '비상구는 어디에 있습니까?'],
      ['zh', 'vi', '请立即停止机器。'],
      ['vi', 'zh', 'Máy số ba đang gặp sự cố.'],
    ];
    var pass = 0;
    for (final s in samples) {
      final from = langByCode(s[0]);
      final to = langByCode(s[1]);
      try {
        for (final l in [from, to]) {
          if (!await _models.isModelDownloaded(l.mlkit.bcpCode)) {
            await _models.downloadModel(l.mlkit.bcpCode, isWifiRequired: false);
          }
        }
        final tr = OnDeviceTranslator(sourceLanguage: from.mlkit, targetLanguage: to.mlkit);
        await tr.translateText('warm up'); // warmup (exclude cold-start)
        const reps = 5;
        var out = '';
        final sw = Stopwatch()..start();
        for (var i = 0; i < reps; i++) {
          out = await tr.translateText(s[2]);
        }
        sw.stop();
        final ms = sw.elapsedMilliseconds / reps;
        await tr.close();
        final ok = out.trim().isNotEmpty && out != s[2];
        if (ok) pass++;
        debugPrint('[VB-TEST] MT ${s[0]}->${s[1]} ${ok ? "OK" : "WEAK"} '
            '${ms.toStringAsFixed(1)}ms/call (best-of-$reps avg): "${s[2]}" => "$out"');
      } catch (e) {
        debugPrint('[VB-TEST] MT ${s[0]}->${s[1]} ERROR: $e');
      }
    }
    debugPrint('[VB-TEST] MT: $pass/${samples.length} pairs OK');

    final pd = pron.apply('Check the ESD mat near the VinFast line.', 'vi');
    debugPrint('[VB-TEST] PRON(vi): "Check the ESD mat near the VinFast line." => "$pd"');

    try {
      final langs = (await _tts.getLanguages as List).map((e) => '$e').toList();
      for (final code in ['vi', 'en', 'ko', 'zh']) {
        final loc = langByCode(code).ttsLocale;
        final has = langs.any((l) => l.toLowerCase() == loc.toLowerCase());
        debugPrint('[VB-TEST] TTS voice $loc available=$has');
      }
    } catch (e) {
      debugPrint('[VB-TEST] TTS getLanguages ERROR: $e');
    }
    for (final t in [
      ['vi', 'Xin chào, đây là VoiceBridge.'],
      ['en', 'Hello, this is VoiceBridge.'],
      ['ko', '안녕하세요.'],
    ]) {
      try {
        await _tts.setLanguage(langByCode(t[0]).ttsLocale);
        final r = await _tts.speak(t[1]);
        debugPrint('[VB-TEST] TTS ${t[0]} speak -> $r');
      } catch (e) {
        debugPrint('[VB-TEST] TTS ${t[0]} ERROR: $e');
      }
      await Future.delayed(const Duration(milliseconds: 1500));
    }

    debugPrint('[VB-TEST] ===== self-test done =====');
    statusMsg = 'Self-test done — MT $pass/${samples.length} OK (see logs)';
    status = PipeStatus.idle;
    notifyListeners();
  }

  /// Full FLORES-200 devtest run of on-device MT across all 6 directions.
  /// Writes hypotheses + timings to the app documents dir for offline scoring.
  /// Trigger: long-press the "Offline" badge.
  Future<void> floresBenchmark() async {
    debugPrint('[VB-BENCH] ===== FLORES benchmark start =====');
    status = PipeStatus.downloading;
    statusMsg = 'FLORES benchmark: loading…';
    notifyListeners();
    final raw = await rootBundle.loadString('assets/bench/flores_sources.json');
    final srcs = json.decode(raw) as Map<String, dynamic>;
    final hyps = <String, List<String>>{};
    final msPer = <String, double>{};
    for (final entry in srcs.entries) {
      final parts = entry.key.split('-');
      final from = langByCode(parts[0]);
      final to = langByCode(parts[1]);
      for (final l in [from, to]) {
        if (!await _models.isModelDownloaded(l.mlkit.bcpCode)) {
          await _models.downloadModel(l.mlkit.bcpCode, isWifiRequired: false);
        }
      }
      final tr = OnDeviceTranslator(sourceLanguage: from.mlkit, targetLanguage: to.mlkit);
      final sents = (entry.value as List).cast<String>();
      final out = <String>[];
      final sw = Stopwatch()..start();
      for (final s in sents) {
        out.add(await tr.translateText(s));
      }
      sw.stop();
      await tr.close();
      hyps[entry.key] = out;
      msPer[entry.key] = sw.elapsedMilliseconds / sents.length;
      debugPrint('[VB-BENCH] ${entry.key}: ${sents.length} sents, '
          '${msPer[entry.key]!.toStringAsFixed(1)} ms/sent');
      statusMsg = 'FLORES: ${entry.key} done';
      notifyListeners();
    }
    final docs = await getApplicationDocumentsDirectory();
    final f = File('${docs.path}/flores_hyps.json');
    await f.writeAsString(json.encode({'hyps': hyps, 'ms_per_sent': msPer}));
    debugPrint('[VB-BENCH] wrote ${f.path}');
    debugPrint('[VB-BENCH] ===== done =====');
    status = PipeStatus.idle;
    statusMsg = 'FLORES benchmark done';
    notifyListeners();
  }

  /// On-device ML Kit OCR benchmark over a pushed corpus, for the PP-OCRv5
  /// hybrid decision. Reads images + manifest from the app external files dir
  /// (`<ext>/ocr_bench/manifest.json` = [{id,lang,file,text}]), runs the
  /// script-appropriate recognizer with warmup + best-of-3 timing, and writes
  /// recognized text + latency to the documents dir for offline CER scoring.
  /// Trigger: long-press the Lens language bar.
  Future<void> ocrBenchmark() async {
    debugPrint('[VB-OCR-BENCH] ===== start =====');
    status = PipeStatus.downloading;
    statusMsg = 'OCR benchmark: loading…';
    notifyListeners();
    final ext = await getExternalStorageDirectory();
    final dir = Directory('${ext?.path}/ocr_bench');
    final manifestFile = File('${dir.path}/manifest.json');
    if (ext == null || !await manifestFile.exists()) {
      debugPrint('[VB-OCR-BENCH] missing ${manifestFile.path}');
      status = PipeStatus.error;
      statusMsg = 'OCR bench: push corpus to ${dir.path}';
      notifyListeners();
      return;
    }
    final items = (json.decode(await manifestFile.readAsString()) as List)
        .cast<Map<String, dynamic>>();
    final recs = <String, TextRecognizer>{};
    TextRecognizer recFor(String lang) =>
        recs.putIfAbsent(lang, () => TextRecognizer(script: _scriptFor(lang)));
    final results = <Map<String, dynamic>>[];
    for (final it in items) {
      final lang = it['lang'] as String;
      final rec = recFor(lang);
      final img = InputImage.fromFilePath('${dir.path}/${it['file']}');
      try {
        await rec.processImage(img); // warmup (not timed)
      } catch (_) {}
      var text = '';
      final us = <int>[];
      for (var i = 0; i < 3; i++) {
        final sw = Stopwatch()..start();
        final r = await rec.processImage(img);
        sw.stop();
        us.add(sw.elapsedMicroseconds);
        text = r.blocks.map((b) => b.text).join(' ').replaceAll('\n', ' ');
      }
      us.sort();
      results.add({
        'id': it['id'],
        'lang': lang,
        'gt': it['text'],
        'hyp': text.trim(),
        'ms_best': us.first / 1000.0,
        'ms_median': us[us.length ~/ 2] / 1000.0,
      });
      debugPrint('[VB-OCR-BENCH] ${it['id']} '
          '${(us.first / 1000.0).toStringAsFixed(1)}ms: "${text.trim()}"');
      statusMsg = 'OCR bench: ${it['id']}';
      notifyListeners();
    }
    for (final r in recs.values) {
      await r.close();
    }
    final docs = await getApplicationDocumentsDirectory();
    final f = File('${docs.path}/ocr_bench_mlkit.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert(results));
    debugPrint('[VB-OCR-BENCH] wrote ${f.path}');
    debugPrint('[VB-OCR-BENCH] ===== done =====');
    status = PipeStatus.idle;
    statusMsg = 'OCR benchmark done (${results.length})';
    notifyListeners();
  }

  /// On-device Whisper STT latency benchmark (recorded-WAV → text decode) for
  /// the on-device latency budget. Reads WAV clips + manifest from
  /// the app external files dir (`<ext>/whisper_latency/manifest.json` =
  /// [{id,lang,file}], lang in ko/zh/en). For each clip it warms up (3 decodes,
  /// discarded — cold-start excluded) then times best-of-5 [WhisperStt.transcribeWav]
  /// calls; since transcribe runs in the worker isolate, the number includes the
  /// real isolate IPC + sherpa decode the user experiences. Writes per-clip
  /// best/median ms to the documents dir for offline aggregation
  /// (`benchmarks/latency/summarize.py`). Requires the Whisper model downloaded.
  /// Trigger: long-press the Settings on-device-speech tile.
  Future<void> whisperLatencyBenchmark() async {
    debugPrint('[VB-LAT] ===== whisper latency benchmark start =====');
    status = PipeStatus.downloading;
    statusMsg = 'Latency benchmark: loading…';
    notifyListeners();
    if (!await whisper.isDownloaded()) {
      status = PipeStatus.error;
      statusMsg = 'Latency bench: download the Whisper model first';
      notifyListeners();
      return;
    }
    final ext = await getExternalStorageDirectory();
    final dir = Directory('${ext?.path}/whisper_latency');
    final manifestFile = File('${dir.path}/manifest.json');
    if (ext == null || !await manifestFile.exists()) {
      debugPrint('[VB-LAT] missing ${manifestFile.path}');
      status = PipeStatus.error;
      statusMsg = 'Latency bench: push clips to ${dir.path}';
      notifyListeners();
      return;
    }
    final items = (json.decode(await manifestFile.readAsString()) as List)
        .cast<Map<String, dynamic>>();
    const warmups = 3, reps = 5;
    final results = <Map<String, dynamic>>[];
    for (final it in items) {
      final lang = it['lang'] as String;
      final wav = '${dir.path}/${it['file']}';
      if (!WhisperStt.handles(lang) || !await File(wav).exists()) {
        debugPrint('[VB-LAT] skip ${it['id']} (lang=$lang or wav missing)');
        continue;
      }
      for (var i = 0; i < warmups; i++) {
        await whisper.transcribeWav(wav, lang); // warmup, not timed
      }
      var hyp = '';
      final us = <int>[];
      for (var i = 0; i < reps; i++) {
        final sw = Stopwatch()..start();
        hyp = await whisper.transcribeWav(wav, lang);
        sw.stop();
        us.add(sw.elapsedMicroseconds);
      }
      us.sort();
      results.add({
        'id': it['id'],
        'lang': lang,
        'hyp': hyp,
        'ms_best': us.first / 1000.0,
        'ms_median': us[us.length ~/ 2] / 1000.0,
        'reps': reps,
      });
      debugPrint('[VB-LAT] ${it['id']} ($lang) '
          'best ${(us.first / 1000.0).toStringAsFixed(1)}ms · '
          'median ${(us[us.length ~/ 2] / 1000.0).toStringAsFixed(1)}ms');
      statusMsg = 'Latency bench: ${it['id']}';
      notifyListeners();
    }
    final docs = await getApplicationDocumentsDirectory();
    final f = File('${docs.path}/whisper_latency.json');
    await f.writeAsString(const JsonEncoder.withIndent('  ').convert({
      'engine': 'whisper-small int8 (sherpa-onnx, CPU, worker isolate)',
      'protocol': 'warmup=$warmups, best-of-$reps, isolate decode incl. IPC',
      'results': results,
    }));
    debugPrint('[VB-LAT] wrote ${f.path}');
    debugPrint('[VB-LAT] ===== done (${results.length} clips) =====');
    status = PipeStatus.idle;
    statusMsg = 'Latency benchmark done (${results.length})';
    notifyListeners();
  }

  /// On-device PP-OCRv5 ONNX latency benchmark across execution providers
  /// (CPU / XNNPACK / NNAPI) for the on-device latency budget. Loads
  /// the models pushed to `<ext>/ocr_bench/models/` and times session.run with
  /// warmup + best-of-N on a representative fixed-shape input (latency is
  /// value-independent, so we feed zeros). Writes ms to the documents dir.
  /// Trigger: long-press the Lens "live" indicator dot.
  TextRecognitionScript _scriptFor(String code) {
    switch (code) {
      case 'ko':
        return TextRecognitionScript.korean;
      case 'zh':
        return TextRecognitionScript.chinese;
      default:
        return TextRecognitionScript.latin; // vi, en
    }
  }

  // Live-overlay OCR: reuse one recognizer + translation cache for smooth frames.
  // The recognizer wraps a native ML Kit pipeline; allocating/closing it per
  // frame stalls the camera stream, so cache it and rebuild only when the
  // source script changes (e.g. user swaps the top language to/from ko/zh).
  TextRecognizer? _liveRec;
  TextRecognitionScript? _liveScript;
  TextRecognizer _liveRecognizer(TextRecognitionScript script) {
    if (_liveRec == null || _liveScript != script) {
      _liveRec?.close();
      _liveRec = TextRecognizer(script: script);
      _liveScript = script;
    }
    return _liveRec!;
  }

  final Map<String, String> _trCache = {};
  Future<String> _trCached(Lang from, Lang to, String src) async {
    final key = '${from.code}|${to.code}|$src';
    final c = _trCache[key];
    if (c != null) return c;
    final raw = await _translate(from, to, src);
    final (dst, _) = glossary.apply(src, raw, from.code, to.code);
    _trCache[key] = dst;
    return dst;
  }

  /// Live camera-frame OCR+translate for the on-screen overlay. Returns each
  /// recognized block with its bounding box (image coords) and translation.
  Future<List<({String src, String dst, double l, double t, double r, double b})>>
      liveOcr(InputImage img) async {
    final from = top, to = bottom;
    final rec = _liveRecognizer(_scriptFor(from.code));
    final out = <({String src, String dst, double l, double t, double r, double b})>[];
    try {
      final res = await rec.processImage(img);
      for (final block in res.blocks) {
        final src = block.text.trim();
        if (src.length < 2) continue;
        final dst = await _trCached(from, to, src);
        final bb = block.boundingBox;
        out.add((src: src, dst: dst, l: bb.left, t: bb.top, r: bb.right, b: bb.bottom));
      }
    } catch (_) {/* skip bad frame */}
    return out;
  }

  /// Boxes from the last OCR capture (for layout-preserving DOCX export).
  List<({String dst, double l, double t, double r, double b})> lastBoxes = [];

  /// OCR an image in the TOP language and translate each text block into the
  /// BOTTOM language (glossary-corrected). For camera/sign translation (Lens).
  ///
  /// Routing:
  ///   ZH / KO → PP-OCRv5 TFLite (NPU, ~2ms, higher ZH accuracy)  [if models present]
  ///   VN / EN / fallback → ML Kit (on-device, handles Vietnamese tones)
  Future<List<({String src, String dst})>> ocrTranslate(String imagePath) async {
    final from = top, to = bottom;

    // Try PP-OCRv5 for ZH/KO when models are available on device.
    if (kPpOcrLangs.contains(from.code) && await PpOcrV5Engine.isAvailable()) {
      debugPrint('[VB-OCR] routing ${from.code} capture through PP-OCRv5 NPU');
      final ppResults = await _ppOcr.recognize(imagePath, from.code);
      if (ppResults.isNotEmpty) {
        final out = <({String src, String dst})>[];
        lastBoxes = [];
        for (final block in ppResults) {
          final src = block.text;
          if (src.isEmpty) continue;
          for (final l in [from, to]) {
            if (!await _models.isModelDownloaded(l.mlkit.bcpCode)) {
              await _models.downloadModel(l.mlkit.bcpCode, isWifiRequired: false);
            }
          }
          final raw = await _translate(from, to, src);
          final (dst, _) = glossary.apply(src, raw, from.code, to.code);
          out.add((src: src, dst: dst));
          lastBoxes.add((dst: dst, l: block.l, t: block.t, r: block.r, b: block.b));
        }
        return out;
      }
      debugPrint('[VB-OCR] PP-OCRv5 returned empty — falling back to ML Kit');
    }

    // ML Kit fallback (always used for VN/EN; fallback for ZH/KO if no NPU models).
    for (final l in [from, to]) {
      if (!await _models.isModelDownloaded(l.mlkit.bcpCode)) {
        await _models.downloadModel(l.mlkit.bcpCode, isWifiRequired: false);
      }
    }
    final recognizer = TextRecognizer(script: _scriptFor(from.code));
    final recognized = await recognizer.processImage(InputImage.fromFilePath(imagePath));
    await recognizer.close();
    final out = <({String src, String dst})>[];
    lastBoxes = [];
    for (final block in recognized.blocks) {
      final src = block.text.trim();
      if (src.isEmpty) continue;
      final raw = await _translate(from, to, src);
      final (dst, _) = glossary.apply(src, raw, from.code, to.code);
      out.add((src: src, dst: dst));
      final bb = block.boundingBox;
      lastBoxes.add((dst: dst, l: bb.left, t: bb.top, r: bb.right, b: bb.bottom));
    }
    return out;
  }

  @override
  void dispose() {
    _stt.cancel();
    _tts.stop();
    _ampSub?.cancel();
    _mic.dispose();
    whisper.dispose();
    _liveRec?.close();
    _ppOcr.dispose();
    super.dispose();
  }
}
