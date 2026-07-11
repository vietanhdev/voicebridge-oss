import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:voicebridge/glossary.dart';
import 'package:voicebridge/model_catalog.dart';
import 'package:voicebridge/settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('defaults load when no prefs', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.load();
    expect(s.tier, Tier.balanced);
    expect(s.ttsRate, closeTo(0.5, 1e-6));
    expect(s.vadHangoverMs, 1600);
    expect(s.domain, Domain.factory);
  });

  test('persisted prefs override defaults', () async {
    SharedPreferences.setMockInitialValues({
      'tier': 'accuracy', 'ttsRate': 0.7, 'vadMs': 2000, 'cont': true, 'domain': 'medical',
    });
    final s = AppSettings();
    await s.load();
    expect(s.tier, Tier.accuracy);
    expect(s.ttsRate, closeTo(0.7, 1e-6));
    expect(s.vadHangoverMs, 2000);
    expect(s.continuousDefault, isTrue);
    expect(s.domain, Domain.medical);
  });

  test('setters clamp + persist', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.load();
    s.setRate(2.0); expect(s.ttsRate, 0.8);
    s.setRate(0.1); expect(s.ttsRate, 0.3);
    s.setVad(50); expect(s.vadHangoverMs, 800);
    s.setVad(99999); expect(s.vadHangoverMs, 2500);
    final p = await SharedPreferences.getInstance();
    expect(p.getDouble('ttsRate'), 0.3);
    expect(p.getInt('vadMs'), 2500);
  });

  test('per-language(-pair) routing: each stage picks the right model', () async {
    SharedPreferences.setMockInitialValues({});
    final s = AppSettings();
    await s.load();
    // Multi-model per language: VN → PhoWhisper specialist; KO/ZH/EN → multilingual workhorse.
    // Accuracy tier: VN→PhoWhisper-medium (9.8%), KO/ZH→turbo (13.8/7.3).
    s.setTier(Tier.accuracy);
    expect(s.asrModelIdForLang('vi'), 'phowhisper_medium');
    expect(s.asrModelIdForLang('ko'), 'whisper_turbo');
    expect(s.asrModelIdForLang('zh'), 'whisper_turbo');
    // Balanced tier: VN→PhoWhisper-small (fast specialist), KO/ZH→Whisper-small.
    s.setTier(Tier.balanced);
    expect(s.asrModelIdForLang('vi'), 'phowhisper_small');
    expect(s.asrModelIdForLang('ko'), 'whisper_small');
    expect(s.asrModelIdForLang('zh'), 'whisper_small');
    // Explicit user override of ASR wins even for VN (escape hatch).
    s.setModel(Stage.asr, 'whisper_turbo');
    expect(s.asrModelIdForLang('vi'), 'whisper_turbo');
    s.setModel(Stage.asr, tierPresets[Tier.balanced]![Stage.asr]!); // clear override
    s.setTier(Tier.accuracy);
    // OCR: VN → VietOCR; ZH/KO → PP-OCRv5; EN → ML Kit
    expect(s.ocrModelIdForLang('vi'), 'vietocr');
    expect(s.ocrModelIdForLang('ko'), 'ppocrv5');
    expect(s.ocrModelIdForLang('en'), 'mlkit_ocr');
    // TTS: ZH → MeloTTS-ZH (Supertonic lacks Chinese); others → tier TTS
    expect(s.ttsModelIdForLang('zh'), 'melotts_zh');
    expect(s.ttsModelIdForLang('vi'), 'supertonic');
    // MT: ZH↔EN → fast OpusMT; other pairs → tier MT (MADLAD on accuracy)
    expect(s.mtModelIdForPair('zh', 'en'), 'opus_zh_en');
    expect(s.mtModelIdForPair('vi', 'ko'), 'madlad_3b');
  });
}
