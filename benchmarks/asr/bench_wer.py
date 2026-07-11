#!/usr/bin/env python3
"""Whisper Tiny WER on a PUBLIC speech dataset (Vietnamese + English).

Dataset:  google/fleurs  (HuggingFace)
  License:      CC-BY-4.0
  Configs:      vi_vn (Vietnamese), en_us (English) — read-aloud, paired with FLORES.
  Acquisition:  datasets.load_dataset("google/fleurs", "<cfg>", split="test")
  Why FLEURS:   no trust_remote_code, clean test split, multilingual, and it pairs with
                the FLORES MT corpus we already bench — consistent eval family.

Model:  openai/whisper-tiny (the same checkpoint compiled to QNN for the S25 NPU).
        WER is model-quality (platform-independent) — it transfers to the on-device
        int8/QNN build modulo quantization, measured separately as latency.

Metric: jiwer WER on lowercased, punctuation-stripped text (standard ASR normalization).

Usage:  python3 bench_wer.py --langs vi_vn en_us --n 50

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import argparse
import json
import re
import unicodedata
from pathlib import Path

HERE = Path(__file__).parent


def norm(s: str) -> str:
    s = unicodedata.normalize("NFC", (s or "").lower())
    s = re.sub(r"[^\w\sàáảãạăằắẳẵặâầấẩẫậèéẻẽẹêềếểễệìíỉĩịòóỏõọôồốổỗộơờớởỡợùúủũụưừứửữựỳýỷỹỵđ]", " ", s)
    return re.sub(r"\s+", " ", s).strip()


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", nargs="+", default=["vi_vn", "en_us"])
    ap.add_argument("--n", type=int, default=50)
    ap.add_argument("--model", default="openai/whisper-tiny")
    a = ap.parse_args()

    import jiwer
    import torch
    from datasets import load_dataset
    from transformers import WhisperForConditionalGeneration, WhisperProcessor

    proc = WhisperProcessor.from_pretrained(a.model)
    model = WhisperForConditionalGeneration.from_pretrained(a.model, torch_dtype=torch.float32).eval()

    results = {}
    for cfg in a.langs:
        lang = cfg.split("_")[0]
        lang = {"cmn": "zh", "yue": "zh"}.get(lang, lang)  # FLEURS code → Whisper lang
        ds = load_dataset("google/fleurs", cfg, split="test", streaming=True)
        refs, hyps = [], []
        for i, ex in enumerate(ds):
            if i >= a.n:
                break
            audio = ex["audio"]["array"]
            sr = ex["audio"]["sampling_rate"]
            feats = proc(audio, sampling_rate=sr, return_tensors="pt").input_features
            with torch.no_grad():
                try:
                    # modern API: language/task as generate kwargs
                    ids = model.generate(feats, language=lang, task="transcribe", max_new_tokens=200)
                except (TypeError, ValueError):
                    try:
                        forced = proc.get_decoder_prompt_ids(language=lang, task="transcribe")
                        ids = model.generate(feats, forced_decoder_ids=forced, max_new_tokens=200)
                    except (TypeError, ValueError):
                        # model has language baked in (e.g. KO-only fine-tune) → no lang kwargs
                        ids = model.generate(feats, max_new_tokens=200)
            hyp = proc.batch_decode(ids, skip_special_tokens=True)[0]
            refs.append(norm(ex["transcription"]))
            hyps.append(norm(hyp))
            if (i + 1) % 10 == 0:
                print(f"  {cfg} {i+1}/{a.n}  running WER={jiwer.wer(refs, hyps):.3f}", flush=True)
        # Chinese has no word boundaries → report CER on whitespace-STRIPPED text
        # (Whisper inserts spaces between Han chars; leaving them inflates CER).
        is_cjk = cfg.startswith("cmn") or cfg.startswith("yue") or lang in ("zh", "cmn")
        if is_cjk:
            refs = [r.replace(" ", "") for r in refs]
            hyps = [h.replace(" ", "") for h in hyps]
        score = jiwer.cer(refs, hyps) if is_cjk else jiwer.wer(refs, hyps)
        metric = "CER" if is_cjk else "WER"
        results[cfg] = {"n": len(refs), metric.lower(): round(score, 4)}
        print(f"=== {cfg}: {metric}={score:.1%} (n={len(refs)}) ===", flush=True)

    out = HERE / "results_whisper_wer_{}.json".format(a.model.split("/")[-1])
    # Merge into any existing file for this model — a re-run with a different
    # --langs subset must not silently discard prior languages' results.
    existing = json.loads(out.read_text()) if out.exists() else {}
    merged_results = {**existing.get("results", {}), **results}
    out.write_text(json.dumps({
        "model": f"{a.model} (float; same ckpt as QNN NPU build)",
        "dataset": "google/fleurs (CC-BY-4.0)",
        "metric": "WER, NFC+lowercase+punct-strip",
        "results": merged_results,
    }, ensure_ascii=False, indent=2))
    print("wrote", out)


if __name__ == "__main__":
    main()
