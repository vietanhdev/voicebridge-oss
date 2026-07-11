#!/usr/bin/env python3
"""PP-OCRv5 accuracy on a PUBLIC, REAL-WORLD Chinese OCR dataset.

Dataset:  SWHL/ChineseOCRBench  (HuggingFace)
  License:      Apache-2.0
  Source:       ReCTS (real store-front / signage photos) + ESTVQA_cn
  Size:         3410 image-answer pairs (test split); we score the ReCTS subset
                (real-world signage — closest to VoiceBridge's industrial domain).
  Acquisition:  `datasets.load_dataset("SWHL/ChineseOCRBench", split="test")`
  Task format:  VQA-style — ground truth is the text of a region in the photo,
                not a full-image transcription.

Why this dataset (real-datasets-only policy): ReCTS images
are genuine photographed Chinese shop signs — real perspective, lighting, fonts,
and clutter — unlike our earlier synthetic corpus. This is the trustable number.

Metric (standard for ChineseOCRBench, per "On the Hidden Mystery of OCR in LMMs"):
  RECOGNITION RECALL — the OCR output (all detected text, concatenated, whitespace
  + punctuation stripped) is checked for the ground-truth answer as a substring.
  We report: recall@full (answer fully contained) and mean char-recall (longest
  common substring / len(answer)). Accuracy is platform-independent (same ONNX
  graph runs identically on desktop and the S25 NPU), so this CER/recall transfers
  to the on-device int8 model modulo quantization (measured separately).

Usage:  python3 bench_public.py [--n 200]
        (uses the PP-OCRv5 zh models in /tmp/ppv5, same as run_ppocrv5.py)

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import argparse
import json
import os
import unicodedata
from pathlib import Path

HERE = Path(__file__).parent
PPV5 = "/tmp/ppv5"
DET = f"{PPV5}/det/det.onnx"
ZH_REC = f"{PPV5}/zh/rec.onnx"


def norm(s: str) -> str:
    """NFC, strip whitespace + common punctuation for fair substring matching."""
    s = unicodedata.normalize("NFC", s or "")
    drop = " \t\n\r,.，。、!?！？:：;；\"'“”‘’()（）[]【】"
    return "".join(c for c in s if c not in drop)


def lcs_len(a: str, b: str) -> int:
    """Longest common substring length (for char-recall)."""
    if not a or not b:
        return 0
    prev = [0] * (len(b) + 1)
    best = 0
    for i in range(1, len(a) + 1):
        cur = [0] * (len(b) + 1)
        for j in range(1, len(b) + 1):
            if a[i - 1] == b[j - 1]:
                cur[j] = prev[j - 1] + 1
                best = max(best, cur[j])
        prev = cur
    return best


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=200, help="ReCTS images to score")
    a = ap.parse_args()

    from datasets import load_dataset
    from rapidocr_onnxruntime import RapidOCR

    ocr = RapidOCR(det_model_path=DET, rec_model_path=ZH_REC, use_angle_cls=False)

    print("Loading SWHL/ChineseOCRBench (test split, streaming)...")
    ds = load_dataset("SWHL/ChineseOCRBench", split="test", streaming=True)

    tmp = HERE / "_pub_tmp.png"
    full_hits, char_recall_sum, scored = 0, 0.0, 0
    misses = []

    for ex in ds:
        if not ex["dataset_name"].startswith("ReCTS"):
            continue
        gt = norm(ex["answers"])
        if len(gt) < 1:
            continue
        ex["image"].convert("RGB").save(tmp)
        res, _ = ocr(str(tmp))
        hyp = norm(" ".join(r[1] for r in res)) if res else ""

        full = gt in hyp
        crec = lcs_len(gt, hyp) / len(gt)
        full_hits += int(full)
        char_recall_sum += crec
        scored += 1
        if not full and len(misses) < 15:
            misses.append({"gt": ex["answers"], "hyp_norm": hyp[:60], "char_recall": round(crec, 2)})
        if scored % 25 == 0:
            print(f"  {scored}/{a.n}  recall@full={full_hits/scored:.1%}  char-recall={char_recall_sum/scored:.1%}")
        if scored >= a.n:
            break

    if tmp.exists():
        tmp.unlink()

    summary = {
        "dataset": "SWHL/ChineseOCRBench (ReCTS subset)",
        "license": "Apache-2.0",
        "n_scored": scored,
        "recall_at_full_pct": round(100 * full_hits / max(1, scored), 2),
        "mean_char_recall_pct": round(100 * char_recall_sum / max(1, scored), 2),
        "model": "PP-OCRv5 det + zh rec (ONNX float32, rapidocr-onnxruntime)",
        "sample_misses": misses,
    }
    out = HERE / "results_public_rects.json"
    out.write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print("\n=== PP-OCRv5 on ReCTS (real signage, public, Apache-2.0) ===")
    print(f"  scored: {scored}")
    print(f"  recall@full:      {summary['recall_at_full_pct']}%")
    print(f"  mean char-recall: {summary['mean_char_recall_pct']}%")
    print(f"  wrote {out}")


if __name__ == "__main__":
    main()
