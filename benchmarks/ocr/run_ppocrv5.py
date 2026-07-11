#!/usr/bin/env python3
"""Run PP-OCRv5 (ONNX) over the sign corpus and emit results for CER scoring.

Pipeline via rapidocr-onnxruntime (Apache-2.0, the de-facto PaddleOCR-on-ORT
wrapper: DB detection postproc + angle cls + CTC decode), with PP-OCRv5 models:
  det = PP-OCRv5 det (monkt/paddleocr-onnx detection/v5)
  rec = per-script PP-OCRv5 rec: zh->chinese, ko->korean, vi->latin
Each language uses its own rec model + char dict — there is NO single
multilingual PP-OCRv5 rec, and the Latin model has no Vietnamese tone marks
(so VI is expected to fail; we run it to *measure* that failure).

ACCURACY is platform-independent (same ONNX graph, same outputs on phone or
desktop), so the CER here is directly comparable to the on-device ML Kit run.
LATENCY here is desktop (CPU or NVIDIA CUDA) and is NOT the S25 Ultra Adreno —
see report. Models are PP-OCRv5 *server*-class rec (heavier than the mobile
rec we'd ship), so desktop latency is an upper bound on model cost, and the
CER is an upper bound on what mobile rec would deliver.

Usage:
  python3 run_ppocrv5.py --device cpu    # writes results_ppocrv5_cpu.json
  python3 run_ppocrv5.py --device cuda   # needs onnxruntime-gpu

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import argparse
import json
import os
import time

from rapidocr_onnxruntime import RapidOCR

HERE = os.path.dirname(os.path.abspath(__file__))
PPV5 = "/tmp/ppv5"  # downloaded models (see report for source URLs)
DET = f"{PPV5}/det/det.onnx"
REC = {"zh": (f"{PPV5}/zh/rec.onnx", f"{PPV5}/zh/dict.txt"),
       "ko": (f"{PPV5}/ko/rec.onnx", f"{PPV5}/ko/dict.txt"),
       "vi": (f"{PPV5}/latin/rec.onnx", f"{PPV5}/latin/dict.txt")}


def engine(lang, cuda):
    # char dict is injected into each rec model's 'character' metadata (see
    # inject step in the report); rapidocr reads it from there.
    rec, _ = REC[lang]
    return RapidOCR(
        det_model_path=DET, rec_model_path=rec,
        use_angle_cls=False,  # signs are upright
        det_use_cuda=cuda, rec_use_cuda=cuda,
    )


def recognize(ocr, path):
    res, _ = ocr(path)
    if not res:
        return ""
    # order top-to-bottom by box top-y, then join lines
    rows = sorted(res, key=lambda r: min(p[1] for p in r[0]))
    return " ".join(r[1].strip() for r in rows).strip()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--device", choices=["cpu", "cuda"], default="cpu")
    a = ap.parse_args()
    cuda = a.device == "cuda"
    gt = json.load(open(os.path.join(HERE, "groundtruth.json"), encoding="utf-8"))

    engines = {l: engine(l, cuda) for l in REC}
    out = []
    for g in gt:
        lang = g["lang"]
        ocr = engines[lang]
        path = os.path.join(HERE, "corpus", g["file"])
        recognize(ocr, path)  # warmup (not timed)
        text, us = "", []
        for _ in range(3):
            t0 = time.perf_counter()
            text = recognize(ocr, path)
            us.append((time.perf_counter() - t0) * 1000.0)
        us.sort()
        out.append({"id": g["id"], "lang": lang, "gt": g["text"], "hyp": text,
                    "ms_best": round(us[0], 1), "ms_median": round(us[1], 1)})
        print(f"{g['id']} {us[0]:6.1f}ms  {text!r}")

    fn = os.path.join(HERE, f"results_ppocrv5_{a.device}.json")
    json.dump(out, open(fn, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print("wrote", fn)


if __name__ == "__main__":
    main()
