// Model catalog — every selectable model per pipeline stage, annotated with the
// REAL on-device numbers measured this benchmark cycle (Qualcomm AI Hub /
// FLORES / FLEURS / ReCTS). Entries with measured=false are roadmap models not
// yet benchmarked on-device — the UI marks them so a choice is never made on a
// fabricated number.
//
// Sources: benchmarks/npu-benchmark.md, benchmarks/mt/, benchmarks/asr/,
// benchmarks/ocr/, benchmarks/tts/.  Author: Viet-Anh Nguyen, Neural Research Lab.

/// Pipeline stage a model serves.
enum Stage { mt, asr, ocr, tts }

/// One selectable model, with measured profile for informed selection.
class ModelSpec {
  final String id;        // stable key stored in prefs
  final String name;      // display name
  final Stage stage;
  final String langs;     // coverage, e.g. 'VN·EN·KO·ZH'
  final String quality;   // measured quality metric, or '—'
  final String latency;   // measured on-device latency, or '—'
  final String license;   // Apache-2.0 / MIT / OpenRAIL-M / proprietary
  final bool measured;    // true => numbers from our committed benches
  const ModelSpec(this.id, this.name, this.stage, this.langs, this.quality,
      this.latency, this.license, this.measured);
}

/// All candidates per stage. First entry in each list is the safe default.
const Map<Stage, List<ModelSpec>> catalog = {
  Stage.mt: [
    ModelSpec('madlad_3b', 'MADLAD-400-3B', Stage.mt, 'VN·EN·KO·ZH',
        '32.01 spBLEU', 'CPU', 'Apache-2.0 ✅', true),
    ModelSpec('gemma4_e2b', 'Gemma 4 E2B', Stage.mt, 'VN·EN·KO·ZH',
        '—', 'on-device', 'Apache-2.0 ✅', false),
    ModelSpec('gemma4_e4b', 'Gemma 4 E4B', Stage.mt, 'VN·EN·KO·ZH',
        '—', 'tablet', 'Apache-2.0 ✅', false),
    ModelSpec('opus_zh_en', 'OpusMT ZH↔EN', Stage.mt, 'ZH·EN only',
        '—', '4.8ms NPU', 'Apache-2.0 ✅', true),
    ModelSpec('mlkit_mt', 'ML Kit', Stage.mt, 'VN·EN·KO·ZH',
        '23.45 spBLEU (KO weak)', 'on-device', 'Google SDK (proprietary)', true),
  ],
  Stage.asr: [
    ModelSpec('phowhisper_small', 'PhoWhisper-small', Stage.asr, 'VN ONLY (✗KO 168%)',
        'VN WER 11.0%', '~78ms NPU', 'BSD-3-Clause', true),
    ModelSpec('whisper_small', 'Whisper Small', Stage.asr, 'VN·EN·ZH·KO (multiling)',
        'VN 21.4% · KO 23.3%', '78ms NPU', 'Apache-2.0', true),
    ModelSpec('whisper_tiny', 'Whisper Tiny', Stage.asr, 'EN·ZH·KO',
        'EN WER 16.6%', '17ms NPU', 'Apache-2.0', true),
    ModelSpec('phowhisper_medium', 'PhoWhisper-medium', Stage.asr, 'VN (specialized)·EN',
        'VN WER 9.8%', '~190ms NPU (tablet)', 'BSD-3-Clause', true),
    ModelSpec('whisper_turbo', 'Whisper large-v3-turbo', Stage.asr, 'VN·EN·KO·ZH (best all)',
        'VN 7.9 · KO 13.8 · ZH 7.3', '~325ms NPU (tablet)', 'MIT', true),
  ],
  Stage.ocr: [
    ModelSpec('mlkit_ocr', 'ML Kit', Stage.ocr, 'VN·EN·KO·ZH',
        '—', '26ms', 'Google SDK (proprietary)', true),
    ModelSpec('ppocrv5', 'PP-OCRv5', Stage.ocr, 'ZH·KO (not VN)',
        'ReCTS 48.5%', '~2ms NPU', 'Apache-2.0', true),
    ModelSpec('vietocr', 'VietOCR', Stage.ocr, 'VN (full tones)',
        '—', 'CNN 4.48ms NPU', 'Apache-2.0', true),
  ],
  Stage.tts: [
    ModelSpec('system_tts', 'System TTS', Stage.tts, 'device langs',
        '—', 'on-device', 'OS', true),
    ModelSpec('supertonic', 'Supertonic-3', Stage.tts, 'VN·EN·KO (not ZH)',
        'RTF 0.20 CPU (5× rt)', 'CPU 4-thr, 44.1kHz', 'OpenRAIL-M ⚠️', true),
    ModelSpec('melotts_zh', 'MeloTTS-ZH', Stage.tts, 'ZH',
        '—', '~160ms NPU', 'MIT', true),
    ModelSpec('kokoro', 'Kokoro', Stage.tts, 'ZH·EN', '—', '—', 'Apache-2.0', false),
    ModelSpec('piper_vi', 'Piper (VN)', Stage.tts, 'VN', '—', '—', 'MIT', false),
  ],
};

ModelSpec? specById(String id) {
  for (final list in catalog.values) {
    for (final m in list) {
      if (m.id == id) return m;
    }
  }
  return null;
}

ModelSpec defaultFor(Stage s) => catalog[s]!.first;
