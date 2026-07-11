# OCR benchmark — ML Kit vs PP-OCRv5 (ZH/KO/VI signs)

Decides the **Lens OCR hybrid**: is PP-OCRv5 worth adding for ZH/KO sign capture,
and can it touch Vietnamese? Bench date **2026-06-06**.

## ⚠️ ACCURACY NUMBERS IN THIS FILE ARE ON SYNTHETIC DATA — NOT TRUSTABLE FOR PUBLICATION
Project policy: never use synthetically generated text/images as the sole accuracy corpus —
use public, realistic datasets. The CER numbers below are **directional only** — they confirm
PP-OCRv5 can output the right characters and that the VN Latin model lacks tone marks. For
publication-quality numbers, see the public ReCTS benchmark (`bench_public.py`).

## TL;DR (synthetic corpus — directional, not publication-grade)
- **ZH:** PP-OCRv5 **wins** — 0.00% CER vs ML Kit 3.11% (fixes real char confusions
  like 佩**戴**→佩**戲**, 通**道**→**逼**道).
- **KO:** tie — both 0.00% CER on this set.
- **VI:** PP-OCRv5 is **unusable** — 53.68% CER (0/10) vs ML Kit 2.78%. The PP-OCRv5
  Latin dict has **no precomposed Vietnamese vowels and no combining marks**, so it
  physically cannot emit `ế ồ ự …`. Measured, not assumed.
- **Decision:** hybrid — **PP-OCRv5 for ZH (and KO, neutral) capture; ML Kit for VN/EN
  and all live overlay.** Never route Vietnamese through PP-OCRv5.

## Accuracy (CER ↓, exact-match, platform-independent)
CER = Levenshtein(gt, hyp) / len(gt) on NFC-normalized, whitespace-collapsed text.
Accuracy is identical on phone or desktop (same ONNX graph), so these compare directly.

| lang | n | ML Kit CER% | ML Kit exact | PP-OCRv5 CER% | PP-OCRv5 exact |
|------|---|-------------|--------------|---------------|----------------|
| ZH   | 10 | 3.11 | 8/10  | **0.00** | **10/10** |
| KO   | 10 | 0.00 | 10/10 | 0.00 | 10/10 |
| VI   | 10 | **2.78** | **6/10** | 53.68 | 0/10 |
| ALL  | 30 | 1.96 | 24/30 | 17.89 | 20/30 |

- ML Kit: `google_mlkit_text_recognition ^0.15.1`, on **S25 Ultra (SM-S938B)**, on-device.
- PP-OCRv5: ONNX via `rapidocr-onnxruntime==1.2.3` (Apache-2.0; DB postproc + CTC).
  Models = `monkt/paddleocr-onnx` (Apache-2.0, no pickle): det `detection/v5`,
  rec `languages/{chinese,korean,latin}` (**server**-class rec; mobile rec would be
  slightly lower accuracy, smaller, faster).

## Latency

### ORT CPU (on-device, S25 Ultra, Snapdragon 8 Elite)
PP-OCRv5 ONNX via `flutter_onnxruntime` (ORT 1.22), per-model best-of-5, fixed input.
EPs reported by the device: `[CPU, NNAPI, XNNPACK]`.

| model | ONNX size | CPU ms | XNNPACK ms | NNAPI ms |
|-------|-----------|--------|------------|----------|
| det (v3, mobile) | 2.4 MB | 129 | 128 | 134 |
| rec zh (**server**) | 81 MB | 178 | 179 | 187 |
| rec ko (mobile) | 13 MB | 42 | 41 | 49 |
| rec latin | 7.6 MB | 46 | 39 | 39 |

**NNAPI does NOT accelerate PP-OCRv5** — it falls back to CPU. Real NPU access needs
the QNN/HTP path via Qualcomm AI Hub compiled models (see below).

### QNN/HTP NPU (Qualcomm AI Hub cloud device — **real S25 Ultra**)
PP-OCRv5 models compiled to int8 `.tflite` via `qai-hub` (v0.50.0) with PTQ calibration,
profiled on a Qualcomm-hosted Samsung Galaxy S25 Ultra. **All layers on NPU — zero CPU fallback.**
Bench date: 2026-06-06. Job IDs: det=jg98xw1qp, zh=jp38we2x5, ko=jgnx7evm5, lat=jgj1wln8g.

| model | ONNX→.tflite size | **NPU ms** | vs ORT CPU | NPU layers |
|-------|-------------------|------------|------------|------------|
| det (v3, mobile) | 2.4 MB → **806 KB** | **1.23** | 129 ms (105×↑) | 156/156 |
| rec zh (server) | 81 MB → **21 MB** | **0.99** | 178 ms (180×↑) | 219/219 |
| rec ko (mobile) | 13 MB → **3.9 MB** | **0.49** | 42 ms (86×↑) | 223/223 |
| rec latin | 7.6 MB → **2.2 MB** | **0.31** | 46 ms (148×↑) | 223/223 |

**Full det+rec pipeline for one ZH/KO sign ≈ 1.23 + 0.99 = ~2.2 ms NPU**.
Compare: ML Kit ~26 ms on same device → **PP-OCRv5 NPU is ~12× faster than ML Kit**.
The ZH NPU model also fixes ML Kit's char-confusions (0.00% vs 3.11% CER). Both win.

ML Kit stays for VN/EN (PP-OCRv5 can't do Vietnamese) and all live overlay.
Desktop CPU pipeline (rapidocr, server models) was ~3050 ms — kept only as a cost sanity check.

## Methodology
- Warmup (≥1, untimed) then **best-of-3** per image; median also recorded.
- Versions + bench date pinned above. Comparison target versioned (`rapidocr 1.2.3`).
- Corpus: **synthetic, clean, printed** industrial-safety signs — 10 each ZH/KO/VI,
  single short phrase, high contrast, no glare/blur/perspective. Measures recognizer
  quality on legible signage, **not** real-world robustness. Small set (30) — treat as
  directional, not a leaderboard. See `make_corpus.py` for the exact register.

## Reproduce
```bash
python3 make_corpus.py                       # 30 ground-truth signs -> corpus/
# ML Kit (on-device): long-press the Lens language bar; pull app_flutter/ocr_bench_mlkit.json
python3 score.py results_mlkit_ondevice.json --label "ML Kit (S25 Ultra)"
# PP-OCRv5 (ONNX): models from monkt/paddleocr-onnx -> /tmp/ppv5/{det,zh,ko,latin}
python3 run_ppocrv5.py --device cpu
python3 score.py results_ppocrv5_cpu.json --label "PP-OCRv5 (ONNX)"
```

## Status / open
- [x] ML Kit baseline on-device (CER + latency).
- [x] PP-OCRv5 accuracy (CER) — decisive, platform-independent.
- [x] **PP-OCRv5 latency on-device (S25 Ultra)** — measured (table above).
  `controller.ortBenchmark()` via `flutter_onnxruntime`, CPU/XNNPACK/NNAPI.
  Result: NNAPI ≈ CPU (no GPU/NPU offload); ~180 ms/sign vs ML Kit ~26 ms.
- [ ] Mobile (not server) PP-OCRv5 ZH rec for a like-for-like shippable ZH latency.
- [ ] **QNN/HTP via Qualcomm AI Hub** compiled models — the preferred route
  and the only path likely to actually beat CPU here (NNAPI didn't).
- [ ] Vietnamese PP-OCRv5 rec: no pretrained model exists (researched 2026-06-06).
  `vi_dict.txt` in the PaddleOCR repo is complete (113 chars, all tones present), but
  no weights use it. Fine-tune `latin_PP-OCRv5_mobile_rec` with `vi_dict.txt` on
  synthetic printed-VN corpus → paddle2onnx → drop-in. **Stretch goal.** VN stays on
  ML Kit until this is trained+benchmarked.
- [ ] Real-world (photographed, glare/angle) corpus for robustness.

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
