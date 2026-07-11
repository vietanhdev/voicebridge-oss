# VoiceBridge — Architecture

VoiceBridge is a fully offline, on-device speech + camera translator for VN ↔ EN/KO/ZH.
No network is used at inference time and no telemetry is emitted. This document describes
how the system is organised and how a spoken turn flows through it.

## Timing tiers

The app is organised into three timing tiers; only the hot tier is on the latency-critical
spoken path, and it contains **no LLM**.

| Tier | When | Contents |
|------|------|----------|
| **Hot** | per utterance | ASR → MT → TTS (and the locked glossary) |
| **Warm** | between turns | glossary growth, error repair, conversational context |
| **Cold** | after a shift | turns conversations into a spaced-repetition review deck |

The glossary is the connective spine: safety-term fidelity in the hot tier, a per-deployment
data asset, and the source material for the learning tier.

## Hot-path data flow (one spoken turn)

```
mic ──▶ VAD endpointing ──▶ ASR (language-routed) ──▶ MT (pair-routed)
                                                          │
                                                          ▼
                                              locked-glossary enforcement
                                                          │
                                                          ▼
              speaker hears  ◀── TTS (target-lang routed) ◀── TTS frontend
                                                       (normalize numbers/units/currency,
                                                        pronunciation respelling)
```

The dual-facing interpreter UI shows each speaker their own language, with the remote panel
rotated 180° for face-to-face use, full-duplex voice-activity detection, and barge-in. In
continuous (hands-free) mode the mic auto-resumes and alternates speakers A→B→A.

## Per-language routing (the core design decision)

No single model is best for all of VN/EN/KO/ZH, so **every stage routes by language (or
language pair)**. A *tier* (Accuracy / Balanced / Light) sets the preference; each stage then
picks the best model for the specific language. Routing lives in `lib/settings.dart`:

- `asrModelIdForLang(src)` — VN → a PhoWhisper specialist; KO/ZH/EN → the tier's multilingual
  Whisper (Whisper-small balanced, Whisper-large-v3-turbo accuracy). PhoWhisper is never used
  for Korean (catastrophic 168% WER), so the router forces a multilingual model there.
- `ocrModelIdForLang(src)` — VN → VietOCR (full tone set; PP-OCRv5 can't encode VN tones),
  ZH/KO → PP-OCRv5, EN → ML Kit.
- `ttsModelIdForLang(tgt)` — ZH → MeloTTS-ZH (Supertonic has no Chinese), else the tier's TTS.
- `mtModelIdForPair(src,tgt)` — ZH↔EN → OpusMT (fast), else the tier's MT.

A user override on any single stage (persisted in `AppSettings.modelOverride`) wins over the
tier preset, so a custom set can be composed on top of a tier. See `docs/models.md` for the
full per-language model table with measured numbers and licenses.

## Speech recognition (ASR)

ASR is the only stage with a non-trivial on-device runtime, so it has two engines:

- **Platform recogniser** (`speech_to_text`) — the default fallback; used for Vietnamese and
  whenever the on-device Whisper model is not downloaded or is disabled.
- **On-device Whisper** (`lib/whisper_stt.dart`, sherpa-onnx / ONNX Runtime) — handles KO/ZH/EN
  when the model is present and on-device STT is enabled. This replaces the weak platform
  Korean recogniser with multilingual Whisper-small. See `docs/on-device-stt.md`.

Endpointing is a shared, ONNX-free **adaptive energy VAD** with hysteresis: speech is entered
at `floor + margin`, held while `floor + margin/2`, and the turn ends after a silence hangover.
The enter margin is user-tunable via the **mic-sensitivity** setting (9 dB loud-only → 3 dB
picks up quiet speech); the ambient floor tracks only when no voice is present, so background
noise raises the bar rather than cutting speech. The Whisper path captures a 16 kHz mono WAV
and decodes it in a dedicated worker isolate (off the UI thread) after the VAD endpoint — it has
no streaming partials — with a hard max-duration cap so a tapped-but-silent mic never records
indefinitely.

## Translation, OCR, TTS

- **MT** ships Google ML Kit on-device today (models for VN/EN/KO/ZH downloaded once). The
  upgrade target is a permissively-licensed MADLAD-400 or a quantised Gemma running on the
  Hexagon NPU; the locked glossary guarantees safety terms regardless of base-MT quality.
- **OCR** (Lens) runs a live camera overlay and a capture→DOCX path (row/column grid). ZH/KO
  capture can use PP-OCRv5 (int8 TFLite, ~2 ms on the NPU), with ML Kit as the always-available
  fallback and the VN/EN path.
- **TTS** uses platform voices today; the neural upgrade is Supertonic-3 (VN/EN/KO) plus
  MeloTTS-ZH for Chinese. A TTS frontend normalises numbers, currency, units, and acronyms,
  and a pronunciation dictionary respells names/jargon (grapheme respelling, engine-agnostic).

## Privacy

All inference is on-device; the app requires no network at inference time and issues no
telemetry. Model files (e.g. the ~375 MB Whisper bundle) download once over the user's
network and are then cached app-private; nothing about a conversation leaves the device.

## Where things live

| Path | Responsibility |
|------|----------------|
| `lib/controller.dart` | hot-path orchestration: STT → MT → TTS, VAD, OCR, glossary |
| `lib/settings.dart` | tiers + per-language/-pair routing functions + persisted overrides |
| `lib/model_catalog.dart` | selectable models per stage with measured profiles |
| `lib/whisper_stt.dart` | on-device Whisper STT (sherpa-onnx): download, load, decode |
| `lib/pp_ocrv5.dart` | PP-OCRv5 TFLite engine (ZH/KO capture) |
| `lib/screens/` | interpreter, lens, glossary, pronunciation, learn, settings |
| `benchmarks/` | runnable bench scripts + reports (ASR, MT, OCR, TTS, NPU) |
