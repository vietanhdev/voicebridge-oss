#!/usr/bin/env python3
"""Quantify the VI<->KO English-pivot penalty, and prove direct MT is the fix.

ROOT CAUSE: Google ML Kit Translation only translates to/from English directly; every
non-English pair pivots through English internally. So the app's VI<->KO is really
VI->EN->KO (double hop), which loses quality — worst on distant pairs like VN<->KO.

EXPERIMENT (same model, isolate the pivot): NLLB-200-distilled-600M (a strong direct
many-to-many MT model) on FLORES VI<->KO:
  - DIRECT:  vi -> ko   and  ko -> vi
  - PIVOT:   vi -> en -> ko   and  ko -> en -> vi   (mimics ML Kit's hop)
Metric: spBLEU (sacrebleu, FLORES-200 spm tokenizer) — same metric as our MT bench.

NLLB is CC-BY-NC (fine for *benchmarking*, NOT for shipping). For the product, ship a
permissively-licensed DIRECT model (Gemma-E2B / MADLAD-400, Apache-2.0). This script's job
is to measure the *pivot penalty*, which transfers to any model.

Dataset: openlanguagedata/flores_plus (CC-BY-SA-4.0) test split, vie_Latn + kor_Hang + eng_Latn.

Usage:  python3 bench_viko.py --n 100

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import argparse
import json
from pathlib import Path

HERE = Path(__file__).parent
# NLLB FLORES codes
LANG = {"vi": "vie_Latn", "ko": "kor_Hang", "en": "eng_Latn"}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--n", type=int, default=100)
    a = ap.parse_args()

    import torch
    import sacrebleu
    from transformers import AutoModelForSeq2SeqLM, AutoTokenizer

    ckpt = "facebook/nllb-200-distilled-600M"
    tok = AutoTokenizer.from_pretrained(ckpt)
    model = AutoModelForSeq2SeqLM.from_pretrained(ckpt).eval()

    # Use the project's own FLORES-1012 asset (index-aligned VI/KO/EN; same corpus the
    # app benchmarks, no gating). vi-en=VI text, ko-vi=KO text, en-vi=EN text.
    flores = json.load(open(HERE.parent.parent / "assets" / "bench" / "flores_sources.json"))
    n = a.n
    src = {
        "vi": flores["vi-en"][:n],
        "ko": flores["ko-vi"][:n],
        "en": flores["en-vi"][:n],
    }

    def translate(texts, src_code, tgt_code):
        tok.src_lang = src_code
        out = []
        bos = tok.convert_tokens_to_ids(tgt_code)
        for t in texts:
            enc = tok(t, return_tensors="pt", truncation=True, max_length=256)
            with torch.no_grad():
                g = model.generate(**enc, forced_bos_token_id=bos, max_new_tokens=256)
            out.append(tok.batch_decode(g, skip_special_tokens=True)[0])
        return out

    def spbleu(hyps, refs):
        return round(sacrebleu.corpus_bleu(hyps, [refs], tokenize="flores200").score, 2)

    results = {}
    # VI -> KO
    direct = translate(src["vi"], LANG["vi"], LANG["ko"])
    pivot_en = translate(src["vi"], LANG["vi"], LANG["en"])
    pivot = translate(pivot_en, LANG["en"], LANG["ko"])
    results["vi->ko"] = {"direct": spbleu(direct, src["ko"]), "pivot_en": spbleu(pivot, src["ko"])}
    print(f"VI->KO  direct={results['vi->ko']['direct']}  pivot(EN)={results['vi->ko']['pivot_en']}", flush=True)
    # KO -> VI
    direct = translate(src["ko"], LANG["ko"], LANG["vi"])
    pivot_en = translate(src["ko"], LANG["ko"], LANG["en"])
    pivot = translate(pivot_en, LANG["en"], LANG["vi"])
    results["ko->vi"] = {"direct": spbleu(direct, src["vi"]), "pivot_en": spbleu(pivot, src["vi"])}
    print(f"KO->VI  direct={results['ko->vi']['direct']}  pivot(EN)={results['ko->vi']['pivot_en']}", flush=True)

    summary = {
        "model": ckpt + " (benchmark only — CC-BY-NC, not for shipping)",
        "dataset": "FLORES-1012 (project assets/bench/flores_sources.json; index-aligned VI/KO/EN)",
        "n": a.n, "metric": "spBLEU (sacrebleu flores200)",
        "results": results,
        "note": "direct vs English-pivot isolates ML Kit's pivot penalty (ML Kit pivots all "
                "non-English pairs through English). Ship a DIRECT Apache model (Gemma-E2B/MADLAD).",
    }
    (HERE / "results_viko_mt.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    print("\n=== VI<->KO: direct vs English-pivot (NLLB-600M, FLORES+) ===")
    for d, r in results.items():
        drop = round(100 * (r["direct"] - r["pivot_en"]) / r["direct"], 1) if r["direct"] else 0
        print(f"  {d}: direct {r['direct']} spBLEU vs pivot {r['pivot_en']} → pivot loses {drop}%")


if __name__ == "__main__":
    main()
