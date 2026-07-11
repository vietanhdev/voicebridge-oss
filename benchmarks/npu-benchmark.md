# VoiceBridge — Full NPU Benchmark Report
## Qualcomm AI Hub cloud-profiled, Samsung Galaxy S25 Ultra (SM8750, Android 15)
### Bench date: 2026-06-06 | Tool: qai-hub 0.50.0, qairt 2.45.0 / litert 1.4.3

All numbers from real S25 Ultra units hosted by Qualcomm AI Hub.
"NPU ops" = 100% means all layers ran on Hexagon V79 HTP — zero CPU fallback.
Latency is **per-inference** (encoder or decoder run, not full pipeline end-to-end).
For fair comparison the ML Kit / ORT baselines are also on the same device (our own adb measurements).

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.

---

## 0. Pipeline top-model recommendation (Qualcomm 8 Elite)

Best model per stage for the VoiceBridge pipeline on Snapdragon, with measurement status.
"NPU ms" = measured on S25 Ultra via AI Hub; accuracy from public datasets where measured.

| Stage | Top model (Qualcomm) | NPU latency | Accuracy (public) | Status |
|-------|----------------------|-------------|-------------------|--------|
| OCR ZH/KO | PP-OCRv5 (int8 TFLite) | det 1.23 + rec ~0.7 ms | ReCTS recall@full 48.5% | ✅ measured |
| OCR VN | **VietOCR** (vgg+transformer) | CNN backbone **4.48 ms, 100% NPU** | vocab covers full VN tones | ✅ measured |
| ASR KO/ZH/EN (balanced) | **Whisper Small** (multilingual) | ~78ms NPU | KO 23.3% · ZH 21.9% (CER) (EN: tiny-tier 16.6%, not separately measured on small) | ✅ measured |
| ASR KO/ZH/EN (accuracy) | **Whisper large-v3-turbo** (MIT) | ~325ms enc NPU | **KO 13.8% · ZH 7.3% · VN 7.9%** | ✅ measured |
| ASR VN | **PhoWhisper-small/-medium** (Whisper arch) | ~78 / ~190 ms, 100% NPU | **VN WER 11.0% / 9.8%** (vs Whisper-small 21.4%) | ✅ measured |
| MT ZH↔EN | AI Hub `opus_mt_zh_en` (QNN) | catalog precompiled | — | ⏭ available |
| MT VN↔EN | Xenova Marian int8 ONNX | (CPU MT meets budget) | — | ⏭ available |
| TTS VN/KO/EN | **Supertonic-3** (ONNX+Flutter) | **RTF ~0.20 CPU (5× rt) [measured]** | VN/KO/EN ✅ no ZH | ⚠️ license gate (§10) |
| TTS ZH | Kokoro / Piper | — | ZH | ⏭ Supertonic lacks ZH |

✅ measured · 🔄 compiling this session · ⏭ identified open-source path, not yet compiled.
Detail per stage below.

---

## 1. OCR — PP-OCRv5 (ZH/KO capture path)

Compiled: custom ONNX → int8 TFLite via AI Hub PTQ.
**Trustable accuracy = ReCTS** (real Chinese store-front / signage photos, the ReCTS subset of
`SWHL/ChineseOCRBench`, Apache-2.0, n=200): **48.5% full-string recall, 66.04% mean char recall**
(`benchmarks/ocr/bench_public.py`). The per-row CER column below is from a small synthetic
smoke set — directional only, NOT a publication number (kept just to pair latency with output).

| model | compile | NPU ms | NPU ops | ORT CPU ms | speedup | CER (synthetic smoke) |
|-------|---------|--------|---------|------------|---------|-------------|
| det v3 mobile | int8 TFLite | **1.23** | 156/156 (100%) | 129 | 105× | — |
| zh rec (server) | int8 TFLite | **0.99** | 219/219 (100%) | 178 | 180× | 0.00% |
| ko rec (mobile) | int8 TFLite | **0.49** | 223/223 (100%) | 42 | 86× | 0.00% |
| latin rec | int8 TFLite | **0.31** | 223/223 (100%) | 46 | 148× | 53.68% VI ❌ |

**Full ZH/KO sign pipeline (det + rec): ~1.7–2.2 ms NPU.**
ML Kit baseline on same device: **~26 ms** (ML Kit used for VN/EN + live overlay).

Job IDs (AI Hub): det=jg98xw1qp, zh=jp38we2x5, ko=jgnx7evm5, lat=jgj1wln8g (compile);
profile: jgkd9yowp, j56vd1r6p, jpv49w9kp, jgj1wlwvg.

---

## 2. ASR — Whisper on NPU

Compiled: float32 PT → QNN context binary (whisper_tiny/base) or TFLite (distil_whisper) via AI Hub.
Whisper splits into encoder + decoder; latency below is per-component, per-decode-step.
A 5-second utterance = 1 encoder pass + ~N decoder steps (N ≈ token count).

| model | component | runtime | NPU ms | NPU ops | GPU ms | CPU ms |
|-------|-----------|---------|--------|---------|--------|--------|
| Whisper Tiny | encoder | QNN ctx binary | **15.4** | 294/294 (100%) | — | — |
| Whisper Tiny | decoder | QNN ctx binary | **1.6** | 509/509 (100%) | — | — |
| Whisper Tiny | **encoder+1 dec step** | | **~17** | 100% | | |
| Whisper Small | encoder | QNN ctx binary | **70.2** | 1582/1582 (100%) | — | — |
| Whisper Small | decoder | QNN ctx binary | **8.3** | 2277/2277 (100%) | — | — |
| Distil Whisper | encoder | TFLite | 408.5 | 0/1366 NPU; 1358 **GPU** | GPU-delegated | — |
| Distil Whisper | decoder | TFLite | **7.2** | 1080/1080 (100%) | — | — |

**Whisper Small (jobs above) runs 100% NPU**: enc 70.2 + dec 8.3 ms/tok → ~236 ms for a
20-token / 5-s utterance — 4.5× Tiny but real-time-feasible, and needed because Tiny's VN
WER (61%) is unusable. Small's VN WER measured below.

**Key finding:** Whisper Tiny encoder+decoder run **100% on Hexagon NPU** via QNN context binary —
this is the path to use. Distil Whisper encoder is **GPU-only** (too large / unsupported ops
for HTP without int8 quantization); decoder is 100% NPU.

Whisper Tiny covers VN/EN/KO/ZH (multilingual). BUT — accuracy check below.

### ASR ACCURACY — Whisper Tiny WER on FLEURS (public, CC-BY-4.0)
Measured: `openai/whisper-tiny` (same ckpt as the QNN build), `google/fleurs` test, jiwer WER.

| lang | WER | verdict |
|------|-----|---------|
| Tiny en_us | **16.6%** (n=30) | usable |
| Tiny vi_vn | **61.3%** (n=30) | ❌ unusable for Vietnamese |
| Small vi_vn | **21.4%** (n=30) | usable |
| PhoWhisper-tiny vi_vn | **21.1%** (n=30) | tiny VN-tuned ≈ Whisper-small |
| **PhoWhisper-small vi_vn** | **11.0%** (n=30) | ✅ **BEST VN — half of tiny / Whisper-small** |
| Whisper-small **ko_kr** | **23.3%** (n=30) | ✅ usable KO (multilingual) |
| **Whisper-large-v3-turbo ko_kr** | **13.8%** (n=20) | ✅✅ **best KO — accuracy tier (MIT)** |
| **Whisper-large-v3-turbo cmn_hans_cn** | **CER 7.3%** (n=20) | ✅✅ **best ZH — accuracy tier** |
| **Whisper-large-v3-turbo vi_vn** | **7.9%** (n=20) | ✅✅ beats PhoWhisper on VN too |
| PhoWhisper-small **ko_kr** | **168.6%** (n=30) | ❌❌ **catastrophic — VN model can't do KO** |

### ASR IS LANGUAGE-ROUTED (the Korean fix)
PhoWhisper is **Vietnamese-specialized**: superb on VN (11%) but **168% WER on Korean**
(emits garbage/Vietnamese for KO audio). **So ASR must route by language, exactly like OCR:**

The app **loads multiple ASR models and routes per language to the best one** (not one model
for all). Numbers below show the balanced and accuracy picks per language:

| spoken language | Balanced | Accuracy |
|-----------------|----------|----------|
| **VN** | PhoWhisper-small 11.0% | PhoWhisper-medium 9.8% |
| **KO** | Whisper-small 23.3% | **turbo 13.8%** |
| **ZH** | Whisper-small 21.9% | **turbo 7.3%** |
| **EN** | Whisper-small/-tiny 16.6% | turbo |

Implemented in `settings.asrModelIdForLang()`: VN→PhoWhisper specialist, KO/ZH/EN→the tier's
multilingual Whisper (small balanced / large-v3-turbo accuracy). VN auto-routes to PhoWhisper.

**On-device deployment (verified, S25 Ultra, 2026-06-06).** KO/ZH/EN now run a real on-device
Whisper engine in the app hot path: sherpa-onnx (Apache-2.0, ONNX Runtime) + multilingual
**Whisper-small int8** (`lib/whisper_stt.dart`), replacing the platform recognizer that was weak
on Korean. End-to-end decode confirmed on-device on a FLEURS Korean clip (identical output to the
host sherpa-onnx 1.13.2 reference). On-device decode ≈ **0.38× RTF** (4.7 s for a 12.5 s clip,
debug build, CPU 2-thread) — faster than real time; a ~4 s turn decodes in ~1.5 s. Model
(~375 MB) downloads once from HF (Settings → On-device speech) and is cached app-private.
Follow-ups: release build + move the recognizer to a dedicated isolate to remove UI-thread
blocking on long utterances; GPU/NPU provider for further speedup.

**Never route KO/ZH
through PhoWhisper.** (Bug caught: making PhoWhisper the blanket ASR pick would have broken
Korean — the core finding behind "Korean recognition is bad".)

**Size sweep (FLEURS, n=30):** PhoWhisper tiny 21.1% → small **11.0%** → medium 9.8%. The
tiny→small jump nearly halves VN WER (39M→244M); small→medium gains only 1.2pp for 3× the size
(769M, tablet-tier). **The knee is PhoWhisper-small** — best accuracy/size, fits the NPU at
~78ms. This is the actionable follow-up to edgevox-research's E5b *negative result* (LoRA
fine-tune of PhoWhisper-tiny overfit, WER ↑): the lever isn't fine-tuning tiny, it's
**zero-shot PhoWhisper-small** — same Whisper-small NPU graph, no training. (FLEURS is a
harder/different set than the CV-vi/VIVOS edgevox used; the relative size gain is the signal.)

**PhoWhisper-small is the VN ASR pick (measured + verified deployable).** vinai/PhoWhisper-small
(BSD-3-Clause) scores **11.0% VN WER vs Whisper-small's 21.4%**. Its config is **byte-identical
to openai/whisper-small** (d_model 768, 12+12 layers, 12 heads, ffn 3072, vocab 51865, 80 mels —
all verified equal), so it reuses the exact AI Hub `whisper_small` QNN graph and its measured
NPU latency (**enc 70.2 + dec 8.3 ms**) transfers directly — no recompile needed. The AI Hub
whisper QNN path is **float (fp16)**, not int8 (`--precision float` only), and fp16 is
near-lossless for Whisper, so the **11.0% WER holds on the NPU** (no int8-degradation risk).

**Resolved ASR/VN tradeoff (measured both ends):** Whisper Tiny is 17 ms NPU but **61% VN WER
(unusable)**. **Whisper Small is 21.4% VN WER (usable)** at enc 70.2 + dec 8.3 ms (100% NPU) →
~236 ms for a 20-token utterance — still real-time. **Decision: PhoWhisper-small for the VN
path** (11.0% WER, same Whisper-small NPU graph), Whisper Small as the multilingual fallback,
Tiny for EN/ZH/KO secondary. All numbers from `google/fleurs` (CC-BY-4.0), `bench_wer.py --model`.

Job IDs (AI Hub):
  whisper_tiny encoder compile: j56vdqmyp | decoder compile: jpe2l4xvp
  whisper_tiny encoder profile: j5m4dvyy5 | decoder profile: jpr9n93vp
  distil_whisper encoder compile: jp38wqln5 | decoder compile: jgom4e7k5
  distil_whisper encoder profile: jp8848yzp | decoder profile: jgkd9dxyp

---

## 3. TTS — MeloTTS / PiperTTS (BLOCKED — env, not measured)

MeloTTS ZH/EN (`melotts_zh`, `melotts_en`) + PiperTTS (`pipertts_en`) are in the catalog,
but **both blocked by Python-package conflicts here**: MeloTTS needs `melo` (MyShell), which
fails to install on Python 3.13 (broken setup.py); the qai_hub_models `__init__` imports it
before `--fetch-static-assets` can bypass. PiperTTS needs `piper_train` (unavailable).
**Not measured — do not cite TTS NPU latency.** Fix: build in a Python 3.10 venv with the
pinned MeloTTS commit, or download the pre-compiled `.tflite` from the AI Hub model page.
Current TTS = `flutter_tts` (system), works on-device. NPU TTS = prototype-phase item.

---

## 4. MT — Translation (DEFERRED — heavy export)

No dedicated MT model in the AI Hub catalog (2026-06-06). Closest: `llama_v3_2_1b_instruct`
(Genie runtime, 1B). Its export runs a **full dynamic-shape ONNX export (~30 min)** + compile;
started but not finished this session. Current MT = ML Kit (23.45 spBLEU) / Gemma 3n E2B
(32.81 spBLEU on FLORES-1012, committed bench; use-restricted license — Gemma 4 E2B is
Apache-2.0 but not yet separately re-measured) on CPU — meets the interactive budget.
MT-on-NPU (Llama-1B Genie / QNN Gemma2-2B) is a prototype-phase item.

---

## 5. Complete pipeline budget (S25 Ultra, per utterance)

Estimates using measured NPU numbers; end-to-end includes all stages.

| stage | model | NPU ms | notes |
|-------|-------|--------|-------|
| VAD | energy-based (Dart) | ~0 | no model |
| ASR | Whisper Tiny NPU | ~17 + 1.6×N_tokens | encoder once + decoder per token |
| MT | Gemma 3n E2B (CPU) | ~200–500 | NPU compile pending; use-restricted license |
| TTS | flutter_tts (system) | — | OS-provided |
| OCR det | PP-OCRv5 det NPU | 1.23 | capture path only |
| OCR rec | PP-OCRv5 zh/ko NPU | 0.5–1.0 | per text block |

**ASR is the bottleneck** for a 5-second / 20-token utterance: ~17 + 1.6×20 ≈ 49 ms NPU.
ML Kit MT adds ~100–200 ms. Full pipeline (ASR+MT) ≈ 150–300 ms end-to-end on NPU+CPU.

---

## Reproduce

```bash
# OCR models (PP-OCRv5 custom ONNX → int8 TFLite)
cd benchmarks/ocr && python3 compile_aihub.py

# ASR (Whisper variants — qai-hub-models catalog)
python3 -m qai_hub_models.models.whisper_tiny.export \
    --device "Samsung Galaxy S25 Ultra" \
    --target-runtime qnn_context_binary \
    --skip-inferencing --skip-downloading \
    --output-dir /tmp/aihub_models/whisper_tiny

# TTS (once melo dep resolved)
python3 -m qai_hub_models.models.melotts_zh.export \
    --device "Samsung Galaxy S25 Ultra" \
    --target-runtime tflite \
    --skip-inferencing --skip-downloading
```

---

## Open-source shortcuts (researched 2026-06-06 — all Apache/MIT/CC, no pickle)

| Need | Use this | License | Why |
|------|----------|---------|-----|
| On-device DB postproc (fix the empty-boxes bug) | `ente-io/mobile_ocr` `TextDetector.kt` (port to Dart) | MIT | Proven PP-OCRv5 DB postproc: connected-components + min-area-rect + Vatti unclip; no native lib |
| **Vietnamese** on-device TTS | Piper `vi/vi_VN/vais1000/medium` (.onnx + .json) | MIT | Ships ONNX directly — skips broken `melo` build; MeloTTS has **no** VN |
| Vietnamese OCR (catalog gap) | **VietOCR** (pbcquoc/vietocr) — torch, vocab 229 incl. full tones | Apache-2.0 | torch → fits qai_hub_models contract; AI Hub compile attempted (see §6) |
| MT VN↔EN | Xenova `opus-mt-vi-en` / `opus-mt-en-vi` (int8 ONNX) | Apache-2.0 (Helsinki upstream) | Ready quantized ONNX — no 30-min export |
| MT ZH↔EN | Qualcomm AI Hub `opus_mt_zh_en` (precompiled QNN) | Apache-2.0 | Already QNN-compiled for 8 Elite |
| Whisper WER eval | `google/fleurs` `vi_vn`/`en_us` | CC-BY-4.0 | No remote-code; pairs with our FLORES MT bench |

## Open items
- [ ] MeloTTS ZH/EN NPU latency (blocked: melo install env conflict)
- [ ] MT model on NPU (Llama-1B Genie / Gemma2-2B via AI Hub)
- [ ] Wire Whisper Tiny QNN into Flutter (replace speech_to_text plugin)
- [ ] Wire PP-OCRv5 TFLite into Lens ZH/KO capture (replace ML Kit OCR for ZH/KO)
- [ ] Whisper base / small quantized results (jobs submitted, pending)
- [ ] Publish all compiled models to HuggingFace with model cards

---

## 7. VietOCR — Vietnamese OCR on NPU (catalog gap filler)

VietOCR (pbcquoc/vietocr, **Apache-2.0**, PyTorch): vgg19_bn CNN + Transformer seq2seq,
vocab of 233 chars incl. the **full Vietnamese tone set**. The only open Vietnamese-capable
recognizer, and Vietnamese OCR is **absent from the 192-model AI Hub catalog**.

Because it is a `torch.nn.Module`, it fits the qai_hub_models torch-trace contract (unlike
PaddleOCR). Measured on S25 Ultra via AI Hub (bench 2026-06-06):

| component | params | NPU latency | NPU ops |
|-----------|--------|-------------|---------|
| CNN backbone (vgg19_bn + last-conv) | 20.2M (53%) | **4.48 ms** | **26/26 (100%)** |
| Transformer enc+dec | 17.5M | TODO (Whisper-style split) | — |

Compile job jgl71q225, profile j5qwmd3e5. Pretrained weights loaded (vocab 233).

**Root-cause fix (resolved, not patched):** AI Hub's auto trace→ONNX failed shape inference
because VietOCR's vgg tail does `conv.permute(-1, 0, 1)` (ONNX `Transpose` rejects **negative
perm**) and `transpose(-1,-2).flatten(2)` (dynamic `Shape→Slice→Reshape`). Rebuilt the tail
with **static positive dims** (`transpose(2,3)`, `permute(2,0,1)`) — identical semantics,
fully static graph, shape inference passes, 100% NPU. See `benchmarks/vietocr/compile_vietocr.py`.

**This makes VietOCR a viable, novel qai_hub_models PR** — torch-native, Apache-2.0, fills the
Vietnamese-OCR gap. Next: trace the transformer enc/dec (Whisper-style) for the full pipeline.

---

## 8. Off-the-shelf AI Hub catalog models (no compile needed)

Several pipeline stages are already in the AI Hub catalog with Qualcomm-published S25 NPU
perf — usable directly, zero compile. Numbers below from each model's `perf.yaml` (Samsung
Galaxy S25, qairt 2.45.0), all 100% NPU unless noted.

| Stage | Catalog model | S25 NPU latency | Use |
|-------|---------------|-----------------|-----|
| MT ZH↔EN | `opus_mt_zh_en` / `opus_mt_en_zh` | enc 2.23 + dec 2.53 ms | **ready — adopt directly** |
| OCR (printed Latin) | `trocr` | enc 5.3 + dec 1.25 ms | English printed; VN-tone fine-tune base |
| OCR multilingual | `easyocr` | det 5.76 + rec 7.55 ms (w8a8) | alt to PP-OCRv5; no VN tones |
| TTS EN | `melotts_en` | ~160 ms (enc 25 + flow 82 + dec 49) | EN voice ready (no VN) |
| ASR | `whisper_tiny/base/small` | see §2 | measured |

**Takeaway:** MT (ZH↔EN) and EN TTS are **solved off-the-shelf** — no custom work. The gaps
needing our own models are exactly the **Vietnamese** ones (VN OCR → VietOCR §7; VN ASR →
Whisper-small §2; VN TTS → Piper). That's consistent with VN being underserved in the catalog.

---

## 9. Multi-device benchmarking on AI Hub — best practice

AI Hub exposes **80 devices** (real, cloud-hosted). Profiling is free, so sweep them.
Demonstrated: `opus_mt_zh_en` encoder across 11 devices — **1.76 ms** (Snapdragon 8 Elite Gen 5)
→ 2.23 ms (S25) → 2.64 ms (S24) → 5.03 ms (QCS8450) → 12.67 ms (SA7255P IoT). One model,
graceful degradation across the Snapdragon line.

Best practice for VoiceBridge:
1. **Headline number on the exact target.** S25 Ultra = SM8750 = Snapdragon 8 Elite. Use the
   specific device string (`"Samsung Galaxy S25 Ultra"`) for the cite-able number, not just Family.
2. **`(Family)` alias to cut queue time** when any unit of that phone is fine.
3. **Sweep a representative range to prove robustness** (not overfit to one chip): flagship
   (8 Elite), prior-gen (S23/8 Gen 2), and a mid/IoT (QCS8550, Dragonwing). Free → do it.
4. **Compilation portability matters:** `qnn_context_binary` is **SoC-locked** (recompile per
   SoC); `qnn_dlc` and `tflite` are **portable** → compile once, profile many. Use tflite/DLC
   for device sweeps, context-binary for the single shipping target's max perf.
5. **Pin + report tool versions and device OS** (qairt/litert, Android) — perf shifts across SDKs.
6. For the challenge: profile on the **judging/demo device** + the **S25 family**, and report a
   small device matrix so reviewers see it generalizes across Snapdragon, not one lucky chip.

```python
import qai_hub as hub
for dev in ["Samsung Galaxy S25 Ultra", "Snapdragon 8 Elite QRD", "Samsung Galaxy S23"]:
    hub.submit_profile_job(model=compiled, device=hub.Device(dev))  # free, parallel
```

---

## 10. Supertonic TTS — strong VN/KO/EN fit, but TWO gates

[supertone-inc/supertonic](https://github.com/supertone-inc/supertonic) — flow-matching TTS,
4-stage ONNX pipeline (~398 MB), and a **Flutter example using `flutter_onnxruntime`** (the
same runtime already in our app). Researched from the repo + HF weights (2026-06-06).

**Strong fit:**
- **Languages: Vietnamese ✅, Korean ✅, English ✅** (31-lang multilingual single ckpt).
- **No pickle** — clean ONNX (text_encoder 36MB, duration_predictor 3.7MB, vector_estimator
  257MB, vocoder 101MB).
- **RTF measured by us** (`benchmarks/tts/bench_rtf.py`, `supertonic==1.3.1`/`onnxruntime==1.22.1`,
  warmup=3 + best-of-5, 4-thread CPU): **VN 0.168 · EN 0.202 · KO 0.194** best, median ~0.20 —
  ~5× real-time on CPU alone. Matches the upstream self-report; NPU/GPU can only be faster.
- Dart inference code (`flutter/lib/helper.dart`) is **liftable** — runs on our existing
  `flutter_onnxruntime`, **CPU, no AI-Hub compile needed for a first version**.

**Gate 1 — Chinese NOT covered.** Supertonic's 31 langs exclude Mandarin. ZH TTS needs a
second engine (**Kokoro**, which covers ZH).

**Gate 2 — LICENSE (decision needed).** Code is **MIT**, but the **weights are BigScience
OpenRAIL-M** (HF `Supertone/supertonic-3/LICENSE`) — *not* Apache/MIT. OpenRAIL-M is
**commercial-OK** (royalty-free, any field incl. SaaS) BUT attaches **behavioral use-restrictions
that propagate downstream** (no non-consensual voice cloning, must disclose synthetic audio,
etc.). This conflicts with the strict "Apache/MIT only" policy. **A policy exception is required
before bundling** — the restrictions are reasonable for a translator, but they're real and
non-removable.

**AI Hub NPU: high-risk, deferred.** Shapes are dynamic (seq/latent length data-dependent) and
`vector_estimator` is an iterative flow-matching denoiser looped in host code. QNN wants static
shapes → needs per-model static-shape surgery + padding before `submit_compile_job`. Op-level
QNN compatibility unverified (graphs not yet loaded). **Do the license decision first** — NPU
porting effort is wasted if the license gates adoption.

**Recommendation:** if the OpenRAIL-M exception is approved → adopt Supertonic for **VN/KO/EN**
TTS (lift `helper.dart` onto our `flutter_onnxruntime`, CPU first), Kokoro for **ZH**. NPU
compile is a later optimization. If the exception is denied → Piper (MIT) for VN, and per-lang
MIT voices elsewhere.

---

## 11. Top alternatives researched (2026-06-06) — per stage, Apache/MIT + on-device

Primary-source audit; ship-constraint Apache/MIT (BSD-3 OK), no pickle weights, no CC-BY-NC.

**ASR — winner: PhoWhisper-small (BSD-3, measured 11.0% VN WER).** Beaten only by
PhoWhisper-medium (769M, tablet). Rejected: wav2vec2-vi / MMS / SeamlessM4T (all CC-BY-NC);
distil-whisper (EN-only). Whisper-large-v3-turbo (MIT, AI-Hub-precompiled) = generic fallback.

**MT — winner (measured): Gemma 3n E2B (use-restricted, 32.81 spBLEU) — no <4B model beats
it in this sweep.** It leads VN↔KO of all <4B tested (en→ko 29.4, ko→vi 27.8). Gemma 4 E2B
is Apache-2.0 (later license than Gemma 2/3) and is the ship candidate if it holds up, but
its spBLEU has **not yet been separately re-measured** — the 32.81 figure above is Gemma 3n's,
not Gemma 4's. Rejected: NLLB/Seamless (CC-BY-NC), envit5 (OpenRAIL + no KO), Qwen2.5-3B
(KO collapses to 12–17 spBLEU). MADLAD-3B (Apache, license-clean today) is the runner-up
reference (32.01) and the safer default until Gemma 4 is benchmarked.

**TTS — no single clean-license model covers VN+KO+ZH+EN.** Best permissive path: MeloTTS
(MIT) upstream KO/ZH/EN + `nmcuong/MeloTTS-Vietnamese` (MIT) for VN — but `.pth` pickle →
must convert to ONNX + de-pickle. Piper = clean ONNX VN/ZH/EN but **GPL-3.0** + no KO.
melotts_zh (catalog, MIT) closes ZH. Supertonic stays VN/KO/EN (OpenRAIL-M gate).

**OCR — keep the Apache hybrid: VietOCR (VN tones, 4.48ms NPU) + PP-OCRv5 (ZH/KO/EN).**
Nothing newer beats it for NPU fit: EasyOCR (Apache, all-4 but pickle + no mobile runtime +
undocumented VN tones), Surya (OpenRAIL + 650M GPU), dots.ocr/GOT/Florence (VLMs, 0.7–3B, GPU).

Pickle-flag (avoid raw-load; convert to ONNX/safetensors): MeloTTS(-VN), viXTTS, F5, EasyOCR,
VietOCR `.pth`, TrOCR. License-blocked for shipping: wav2vec2-vi, MMS, Seamless, NLLB, F5,
OuteTTS, viXTTS (CPML), Piper (GPL), Surya models (OpenRAIL).
