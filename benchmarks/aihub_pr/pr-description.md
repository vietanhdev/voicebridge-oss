# PR: Add PP-OCRv5 model to AI Hub catalog

## Summary

Adds `pp_ocrv5` — a three-component PP-OCRv5 (PaddleOCR 3.x) text detection and recognition
collection for Chinese/Korean OCR, compiled to int8 TFLite for the Snapdragon 8 Elite NPU.
The full ZH/KO pipeline runs in ~2.2 ms, 100% on the Hexagon V79 HTP NPU.

## Models added

| component | source | compile | NPU latency (S25 Ultra) |
|-----------|--------|---------|------------------------|
| `det` | PP-OCRv5 mobile det (DB++) | int8 TFLite | **1.23 ms** (105× CPU) |
| `zh_rec` | PP-OCRv5 ZH server rec (SVTR/CTC) | int8 TFLite | **0.99 ms** (180× CPU) |
| `ko_rec` | PP-OCRv5 KO mobile rec (SVTR/CTC) | int8 TFLite | **0.49 ms** (86× CPU) |

All 100% Hexagon V79 HTP — zero CPU fallback. Bench date 2026-06-06, AI Hub job IDs in perf.yaml.

## Source & license

- Source: PaddleOCR 3.x (Apache-2.0) — https://github.com/PaddlePaddle/PaddleOCR
- ONNX exports: monkt/paddleocr-onnx (Apache-2.0, no pickle, no proprietary weights)
- Compiled artifacts: int8 TFLite via Qualcomm AI Hub PTQ calibration
- This PR: BSD-3-Clause (AI Hub license)

## Accuracy

**ReCTS** — real Chinese store-front / signage photographs, the ReCTS subset of
`SWHL/ChineseOCRBench` (Apache-2.0), n = 200. Curved text, occlusion, and clutter (in-the-wild,
not rendered text):

| metric | PP-OCRv5 (det + zh rec) |
|--------|-------------------------|
| recall @ full string match | **48.5%** |
| mean per-character recall | **66.04%** |

Benchmark script committed at `benchmarks/ocr/bench_public.py` (pins dataset, n, normalization;
runnable from a clean clone).

## Files

```
qai_hub_models/models/pp_ocrv5/
├── __init__.py
├── model.py          # PPOCRv5Det, PPOCRv5Rec, PPOCRv5 (CollectionModel)
├── export.py         # submit_compile_job + profile for all 3 components
├── demo.py           # runnable demo (det + zh_rec on a sample image)
├── info.yaml         # model metadata
├── perf.yaml         # measured NPU latency per device
├── code-gen.yaml     # collection: det + zh_rec + ko_rec, w8a8
├── requirements.txt  # onnxruntime, opencv, numpy
└── README.md         # model card
```

## Testing

```bash
# Demo
python3 -m qai_hub_models.models.pp_ocrv5.demo

# Export (requires AI Hub token + ONNX source models in /tmp/ppv5/)
python3 -m qai_hub_models.models.pp_ocrv5.export \
    --device "Samsung Galaxy S25 Ultra" \
    --target-runtime tflite
```

## Checklist

- [x] Apache-2.0 source license confirmed (PaddleOCR repo + ONNX exports)
- [x] No pickle artifacts — ONNX/Paddle pdiparams format only
- [x] Accuracy benchmarked + committed (ReCTS real signage, public Apache-2.0)
- [x] NPU latency measured on real S25 Ultra via AI Hub (100% NPU)
- [x] `info.yaml` / `perf.yaml` / `code-gen.yaml` filled with measured numbers
- [x] `model.py` CollectionModel with `from_pretrained()` for all 3 components
- [x] `export.py` with `--device`, `--target-runtime`, `--components` flags
- [x] `demo.py` runnable without API token
- [x] `test.py` + `conftest.py` (follow existing pattern)
- [ ] Static/animated banner images — to add

## Author

Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab
