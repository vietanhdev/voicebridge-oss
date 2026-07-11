import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'glossary.dart';
import 'model_catalog.dart';

/// Quality tier the user picks; each stage maps to a benchmarked catalog model.
enum Tier { accuracy, balanced, light }

/// Tier presets — each stage references a [catalog] model id. Grounded in the
/// committed benchmarks (see model_catalog.dart). A user can override any single
/// stage (see AppSettings.modelOverride) to compose a custom good set.
const Map<Tier, Map<Stage, String>> tierPresets = {
  // ASR base = MULTILINGUAL Whisper (covers VN/EN/KO/ZH); Vietnamese auto-upgrades to
  // PhoWhisper via asrModelIdForLang() (PhoWhisper is VN-only — KO WER 168%, unusable).
  // MT default = MADLAD-3B (Apache-2.0, 32.01 spBLEU) — license-clean. Gemma 4 E2B/E4B
  // (Apache-2.0) are available as overrides — license-clean on-device upgrades (benchmark TBD).
  // ASR is the MULTILINGUAL workhorse for KO/ZH/EN; VN always routes to a PhoWhisper
  // specialist (see asrModelIdForLang) — the app loads MULTIPLE ASR models, best-per-lang.
  // Accuracy ASR = Whisper large-v3-turbo (MIT): KO 13.8 / ZH 7.3 (FLEURS), big win over
  // Whisper-small (23.3 / 21.9). VN→PhoWhisper-medium 9.8%. Heavier (~325ms NPU, tablet).
  Tier.accuracy: {Stage.mt: 'madlad_3b', Stage.asr: 'whisper_turbo', Stage.ocr: 'ppocrv5', Stage.tts: 'supertonic'},
  Tier.balanced: {Stage.mt: 'mlkit_mt', Stage.asr: 'whisper_small', Stage.ocr: 'ppocrv5', Stage.tts: 'system_tts'},
  Tier.light:    {Stage.mt: 'mlkit_mt', Stage.asr: 'whisper_tiny', Stage.ocr: 'mlkit_ocr', Stage.tts: 'system_tts'},
};

/// Persisted user prefs. All values clamped to safe ranges; defaults match the
/// app's current behaviour so existing users see no change unless they tweak.
class AppSettings extends ChangeNotifier {
  Tier tier = Tier.balanced;
  double ttsRate = 0.5;          // 0.3 (slow) … 0.8 (fast)
  int vadHangoverMs = 1600;      // 800 (snappy) … 2500 (patient)
  double micSensitivity = 0.6;   // 0 (only loud speech) … 1 (picks up whispers)
  bool continuousDefault = false;
  bool ocrLiveDefault = true;
  bool autoApplyGlossary = true;
  bool useOnDeviceStt = true;    // route KO/ZH/EN to on-device Whisper when downloaded
  Domain domain = Domain.factory;

  /// Per-stage model override (stage.name -> catalog model id). Empty = use the
  /// tier preset. Lets the user compose a custom set on top of a tier.
  final Map<String, String> modelOverride = {};

  SharedPreferences? _p;
  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    final t = _p!.getString('tier');
    if (t != null) tier = Tier.values.firstWhere((x) => x.name == t, orElse: () => Tier.balanced);
    ttsRate = _p!.getDouble('ttsRate') ?? ttsRate;
    vadHangoverMs = _p!.getInt('vadMs') ?? vadHangoverMs;
    micSensitivity = _p!.getDouble('mic') ?? micSensitivity;
    continuousDefault = _p!.getBool('cont') ?? continuousDefault;
    ocrLiveDefault = _p!.getBool('live') ?? ocrLiveDefault;
    autoApplyGlossary = _p!.getBool('glos') ?? autoApplyGlossary;
    useOnDeviceStt = _p!.getBool('ondevstt') ?? useOnDeviceStt;
    final d = _p!.getString('domain');
    if (d != null) domain = Domain.values.firstWhere((x) => x.name == d, orElse: () => Domain.factory);
    for (final st in Stage.values) {
      final ov = _p!.getString('model_${st.name}');
      if (ov != null && specById(ov) != null) modelOverride[st.name] = ov;
    }
  }

  void setDomain(Domain d) { domain = d; _p?.setString('domain', d.name); notifyListeners(); }

  void setTier(Tier t) { if (t == tier) return; tier = t; _p?.setString('tier', t.name); notifyListeners(); }

  /// Effective model id for a stage: user override if set, else the tier preset.
  String modelId(Stage s) => modelOverride[s.name] ?? tierPresets[tier]![s]!;

  /// Resolved [ModelSpec] for a stage.
  ModelSpec specFor(Stage s) => specById(modelId(s)) ?? defaultFor(s);

  /// ASR is LANGUAGE-ROUTED (like OCR). PhoWhisper is Vietnamese-specialized — it
  /// regresses badly on KO/ZH, so only Vietnamese routes to it; every other language
  /// uses the tier's MULTILINGUAL Whisper. Returns the catalog id to use for [langCode].
  String asrModelIdForLang(String langCode) {
    final overridden = modelOverride.containsKey(Stage.asr.name);
    final picked = modelId(Stage.asr); // the tier's MULTILINGUAL workhorse (KO/ZH/EN)
    if (langCode == 'vi') {
      if (overridden) return picked; // user explicitly chose an ASR model → respect it
      // VN gets a Vietnamese-SPECIALIST, never the generic multilingual model. Accuracy
      // tier affords the larger PhoWhisper-medium (FLEURS 9.8%); balanced/light use the
      // fast PhoWhisper-small (11.0%, ~78ms NPU). Both beat any multilingual Whisper on VN.
      return tier == Tier.accuracy ? 'phowhisper_medium' : 'phowhisper_small';
    }
    // KO / ZH / EN: PhoWhisper is VN-only (KO WER 168%) → never route here; fall back to
    // Whisper-small. Otherwise use the tier workhorse (turbo on accuracy: KO 13.8/ZH 7.3).
    return picked.startsWith('phowhisper') ? 'whisper_small' : picked;
  }

  /// Resolved ASR [ModelSpec] for a specific language (language-routed).
  ModelSpec asrSpecForLang(String langCode) =>
      specById(asrModelIdForLang(langCode)) ?? defaultFor(Stage.asr);

  /// OCR routes by SOURCE language: VN → VietOCR (full tones; PP-OCRv5 can't do VN),
  /// ZH/KO → PP-OCRv5, EN → ML Kit. Honors a user override when set.
  String ocrModelIdForLang(String langCode) {
    if (modelOverride.containsKey(Stage.ocr.name)) return modelOverride[Stage.ocr.name]!;
    if (langCode == 'vi') return 'vietocr';
    if (langCode == 'ko' || langCode == 'zh') return 'ppocrv5';
    return 'mlkit_ocr';
  }

  /// TTS routes by TARGET language: ZH → melotts_zh (Supertonic has no Chinese);
  /// VN/KO/EN → the tier's TTS (Supertonic / system). Honors a user override.
  String ttsModelIdForLang(String langCode) {
    final picked = modelId(Stage.tts);
    if (modelOverride.containsKey(Stage.tts.name)) return picked;
    if (langCode == 'zh' && picked == 'supertonic') return 'melotts_zh'; // Supertonic lacks ZH
    return picked;
  }

  /// MT routes by PAIR: ZH↔EN → OpusMT (fast NPU, 4.8ms) when not overridden;
  /// every other pair → the tier's MT (MADLAD / Gemma / ML Kit). Honors override.
  String mtModelIdForPair(String fromCode, String toCode) {
    final picked = modelId(Stage.mt);
    if (modelOverride.containsKey(Stage.mt.name)) return picked;
    final pair = {fromCode, toCode};
    if (pair.containsAll({'zh', 'en'})) return 'opus_zh_en';
    return picked;
  }

  /// Override (or clear, when [id] equals the tier preset) one stage's model.
  void setModel(Stage s, String id) {
    if (specById(id) == null) return;
    if (id == tierPresets[tier]![s]) {
      modelOverride.remove(s.name);
      _p?.remove('model_${s.name}');
    } else {
      modelOverride[s.name] = id;
      _p?.setString('model_${s.name}', id);
    }
    notifyListeners();
  }

  /// True when any stage diverges from the current tier preset.
  bool get isCustom => Stage.values.any((s) => modelOverride.containsKey(s.name)
      && modelOverride[s.name] != tierPresets[tier]![s]);
  void setRate(double v) { ttsRate = v.clamp(0.3, 0.8); _p?.setDouble('ttsRate', ttsRate); notifyListeners(); }
  void setVad(int ms) { vadHangoverMs = ms.clamp(800, 2500); _p?.setInt('vadMs', vadHangoverMs); notifyListeners(); }
  void setMicSensitivity(double v) { micSensitivity = v.clamp(0.0, 1.0); _p?.setDouble('mic', micSensitivity); notifyListeners(); }

  /// dB margin above the ambient noise floor at which speech is *entered*. High
  /// sensitivity → low gate (picks up quiet speech); low sensitivity → high gate
  /// (ignores background talk). Maps 0→9dB … 1→3dB. Exit gate is half of this.
  double get vadEnterMarginDb => 9.0 - 6.0 * micSensitivity;
  void setContinuous(bool v) { continuousDefault = v; _p?.setBool('cont', v); notifyListeners(); }
  void setOcrLive(bool v) { ocrLiveDefault = v; _p?.setBool('live', v); notifyListeners(); }
  void setGlossary(bool v) { autoApplyGlossary = v; _p?.setBool('glos', v); notifyListeners(); }
  void setOnDeviceStt(bool v) { useOnDeviceStt = v; _p?.setBool('ondevstt', v); notifyListeners(); }

  /// Display map stage.name -> model display name, for the effective set.
  Map<String, String> get models =>
      {for (final s in Stage.values) s.name: specFor(s).name};
}
