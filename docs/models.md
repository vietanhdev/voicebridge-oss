# VoiceBridge — Model Pipeline Reference

Every model in the pipeline, with the **measured** numbers used to select it, its license, and
its source. All numbers come from committed bench scripts on public datasets — never estimates.
The catalog is mirrored in code at `lib/model_catalog.dart`; routing is in `lib/settings.dart`.

> Selection policy: ship Apache/MIT/BSD by default; state corpus size for every quality metric;
> warm-up + best-of-N for latency; real public datasets only (no synthetic-as-sole-corpus).

## Quality tiers

A tier sets each stage's preferred model; per-language routing then refines it, and a user
override on any stage wins. Tiers are defined in `tierPresets` (`lib/settings.dart`).

| Tier | ASR (multilingual workhorse) | MT | OCR | TTS |
|------|------------------------------|----|-----|-----|
| Accuracy | Whisper-large-v3-turbo | MADLAD-3B | PP-OCRv5 | Supertonic-3 |
| Balanced | Whisper-small | ML Kit | PP-OCRv5 | System |
| Light | Whisper-tiny | ML Kit | ML Kit | System |

VN always routes to a PhoWhisper specialist regardless of tier; ZH↔EN MT routes to OpusMT;
ZH TTS routes to MeloTTS-ZH. (See routing functions below.)

## ASR — speech recognition

Dataset: **FLEURS** (`google/fleurs`, CC-BY-4.0), WER (CER for Chinese). Numbers are a
preliminary 20–30-utterance/language subset (`benchmarks/asr/bench_wer.py`); full-test eval
is roadmap. PhoWhisper reuses the Whisper-small architecture so it shares the NPU graph.

| Model | Langs | WER / CER | License | Note |
|-------|-------|-----------|---------|------|
| PhoWhisper-small | VN only | **VN 11.0%** | BSD-3 | VN specialist; KO **168%** ✗ — never route KO/ZH here |
| PhoWhisper-medium | VN only | VN 9.8% | BSD-3 | tablet-tier VN |
| Whisper-small | VN·EN·ZH·KO | KO 23.3 · ZH 21.9 (CER) · VN 21.4 · EN not separately measured | Apache-2.0 | balanced multilingual |
| Whisper-tiny | EN·ZH·KO | EN 16.6 | Apache-2.0 | light tier |
| **Whisper-large-v3-turbo** | VN·EN·KO·ZH | **KO 13.8 · ZH 7.3 · VN 7.9** | MIT | accuracy tier; best on every language |

**Deployed on-device:** KO/ZH/EN run Whisper-small via sherpa-onnx (see `docs/on-device-stt.md`),
verified on the S25 Ultra at ~0.38× RTF. VN uses PhoWhisper / platform STT.

## MT — translation

Dataset: **FLORES-200 devtest** (1012 sentences/direction), spBLEU via sacreBLEU
(`benchmarks/mt/`). Mean over the six challenge directions.

| Model | Mean spBLEU | License | Note |
|-------|-------------|---------|------|
| ML Kit | 23.45 | Google SDK (proprietary) | ships today, fully on-device, KO weak |
| **MADLAD-400-3B** | **32.01** | Apache-2.0 | license-clean default / NPU upgrade target |
| Gemma 3n E2B | 32.81 | Gemma Terms (use-restricted) | highest quality, **not** Apache — option only |
| OpusMT ZH↔EN | — | Apache-2.0 | fast NPU path for the ZH↔EN pair |

## OCR — camera text

Dataset: **ReCTS** (real Chinese store-front signage, ReCTS subset of
`SWHL/ChineseOCRBench`, Apache-2.0, n=200) — `benchmarks/ocr/bench_public.py`. (An earlier
synthetic corpus is retained only as a directional smoke set, not a publication number.)

| Model | Langs | Accuracy | NPU latency | License |
|-------|-------|----------|-------------|---------|
| PP-OCRv5 | ZH·KO (not VN) | ReCTS 48.5% full recall, 66.0% char | det 1.23 + rec ~0.7 ms | Apache-2.0 |
| VietOCR | VN (full tones) | latency only; accuracy TBD | CNN 4.48 ms | Apache-2.0 |
| ML Kit | VN·EN·KO·ZH | — | ~26 ms | Google SDK |

PP-OCRv5's Latin dict cannot encode Vietnamese tone marks, so VN never routes to it.

## TTS — speech synthesis

| Model | Langs | Measured | License |
|-------|-------|----------|---------|
| Supertonic-3 | VN·EN·KO (not ZH) | RTF best VN 0.168 / EN 0.202 / KO 0.194 (≈5× real-time, CPU) | MIT code / OpenRAIL-M weights |
| MeloTTS-ZH | ZH | ~160 ms NPU | MIT |
| System TTS | device langs | on-device | OS |

Supertonic RTF: `benchmarks/tts/bench_rtf.py` (warm-up 3 + best-of-5, 4-thread CPU,
`supertonic==1.3.1` / `onnxruntime==1.22.1`). OpenRAIL-M is commercial-OK but carries
behavioural use-restrictions → a license-policy decision before bundling.

## Routing functions (`lib/settings.dart`)

| Function | Rule |
|----------|------|
| `asrModelIdForLang(lang)` | VN → PhoWhisper (medium on accuracy, small otherwise); KO/ZH/EN → tier's multilingual Whisper (PhoWhisper forced off for non-VN) |
| `ocrModelIdForLang(lang)` | VN → VietOCR; ZH/KO → PP-OCRv5; EN → ML Kit |
| `ttsModelIdForLang(lang)` | ZH → MeloTTS-ZH; else tier TTS |
| `mtModelIdForPair(a,b)` | ZH↔EN → OpusMT; else tier MT |

## Adding or swapping a model

1. Add a `ModelSpec` to `catalog` in `lib/model_catalog.dart` with its **measured** quality,
   latency, and license. Set `measured: false` until a committed bench produces real numbers
   (the UI shows a "planned" chip and the tier defaults avoid it).
2. If it should be auto-selected for a language/pair, update the relevant routing function in
   `lib/settings.dart` and add a routing assertion to `test/settings_test.dart`.
3. Commit the bench script + result JSON under `benchmarks/<stage>/` in the same change, and
   update `README.md` / `benchmarks/npu-benchmark.md` if the pick changes.
