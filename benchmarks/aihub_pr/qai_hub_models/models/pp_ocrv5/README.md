# PP-OCRv5

PP-OCRv5 (PaddleOCR v5) text detection and Chinese/Korean recognition, compiled for the
Snapdragon 8 Elite NPU via Qualcomm AI Hub.

## Overview

This model collection provides three components of the PaddleOCR v5 pipeline:

| Component | Description | Input shape | NPU latency (S25 Ultra) |
|-----------|-------------|-------------|------------------------|
| `det` | PP-OCRv5 mobile text detection (DB++) | 1×3×640×640 | **1.23 ms** |
| `zh_rec` | PP-OCRv5 ZH rec (SVTR/CTC, 18k dict) | 1×3×48×W | **0.99 ms** |
| `ko_rec` | PP-OCRv5 KO rec (SVTR/CTC, 12k dict) | 1×3×48×W | **0.49 ms** |

**Full ZH/KO pipeline ≈ 2.2 ms on Hexagon V79 HTP NPU — 100% NPU, zero CPU fallback.**

## Accuracy

Measured on **ReCTS** (real Chinese store-front / signage photographs), the ReCTS subset of
[`SWHL/ChineseOCRBench`](https://huggingface.co/datasets/SWHL/ChineseOCRBench) (Apache-2.0),
n = 200 images. ReCTS contains curved text, occlusion, and background clutter — a realistic
in-the-wild signage benchmark, not clean rendered text.

| metric | PP-OCRv5 (det + zh rec) |
|--------|-------------------------|
| recall @ full string match | **48.5%** |
| mean per-character recall | **66.04%** |

Benchmark script: `benchmarks/ocr/bench_public.py` (runnable from a clean clone; pins the
dataset, n, and normalization).

## Latency vs. a typical on-device OCR SDK

On-device latency is value-independent; PP-OCRv5 on the NPU runs the full ZH/KO pipeline in
~2.2 ms vs. ~26 ms for a typical mobile OCR SDK on the same device — roughly **12× faster**.

## Usage (compiled artifact)

```python
from qai_hub_models.models.pp_ocrv5.export import export
jobs = export(device="Samsung Galaxy S25 Ultra", target_runtime="tflite")
```

## Source models

Apache-2.0 ONNX exports from [`monkt/paddleocr-onnx`](https://huggingface.co/monkt/paddleocr-onnx).
Original: [PaddleOCR 3.x](https://github.com/PaddlePaddle/PaddleOCR) (Apache-2.0).

## Citation

```bibtex
@misc{ppocrv5_snapdragon_2026,
  author = {Nguyen, Viet-Anh and {Neural Research Lab}},
  title  = {PP-OCRv5 compiled for the Snapdragon NPU via Qualcomm AI Hub},
  year   = {2026}
}
@misc{paddleocr30,
  title        = {PaddleOCR 3.0 Technical Report},
  howpublished = {\url{https://arxiv.org/abs/2507.05595}},
  year         = {2025}
}
```

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
