#!/usr/bin/env python3
"""Score an OCR results file against ground truth: CER + exact-match per language.

Results file = JSON list of {id, lang, gt, hyp, [ms_best, ms_median]}.

CER = Levenshtein(gt, hyp) / len(gt), computed on NFC-normalized,
whitespace-collapsed strings (runs of whitespace -> single space, stripped).
This measures character recognition, folding away line-break/spacing layout
differences between recognizers. We also report exact-match rate (fraction of
signs recognized perfectly after that normalization) and median latency.

Usage:  python3 score.py results_mlkit_ondevice.json [--label "ML Kit (on-device)"]

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import argparse
import json
import sys
import unicodedata


def norm(s):
    s = unicodedata.normalize("NFC", s or "")
    return " ".join(s.split())


def lev(a, b):
    if a == b:
        return 0
    if not a:
        return len(b)
    if not b:
        return len(a)
    prev = list(range(len(b) + 1))
    for i, ca in enumerate(a, 1):
        cur = [i]
        for j, cb in enumerate(b, 1):
            cur.append(min(prev[j] + 1, cur[j - 1] + 1, prev[j - 1] + (ca != cb)))
        prev = cur
    return prev[-1]


def score(path, label):
    data = json.load(open(path, encoding="utf-8"))
    by_lang = {}
    for r in data:
        gt, hyp = norm(r["gt"]), norm(r["hyp"])
        cer = lev(gt, hyp) / max(1, len(gt))
        rec = by_lang.setdefault(r["lang"], {"cer": [], "exact": 0, "n": 0, "ms": []})
        rec["cer"].append(cer)
        rec["exact"] += int(gt == hyp)
        rec["n"] += 1
        if "ms_best" in r:
            rec["ms"].append(r["ms_best"])

    print(f"\n=== {label} ===")
    print(f"{'lang':<6}{'n':>4}{'CER%':>8}{'exact':>9}{'ms_best_med':>13}")
    allc, alln, allx, allms = [], 0, 0, []
    for lang in sorted(by_lang):
        v = by_lang[lang]
        cer = 100 * sum(v["cer"]) / v["n"]
        ms = sorted(v["ms"])
        msmed = ms[len(ms) // 2] if ms else float("nan")
        print(f"{lang:<6}{v['n']:>4}{cer:>8.2f}{v['exact']:>5}/{v['n']:<3}{msmed:>13.1f}")
        allc += v["cer"]
        alln += v["n"]
        allx += v["exact"]
        allms += v["ms"]
    cer = 100 * sum(allc) / alln
    allms.sort()
    msmed = allms[len(allms) // 2] if allms else float("nan")
    print(f"{'ALL':<6}{alln:>4}{cer:>8.2f}{allx:>5}/{alln:<3}{msmed:>13.1f}")
    return {
        "label": label,
        "overall_cer_pct": round(cer, 2),
        "overall_exact": f"{allx}/{alln}",
        "per_lang": {
            l: {
                "cer_pct": round(100 * sum(v["cer"]) / v["n"], 2),
                "exact": f"{v['exact']}/{v['n']}",
            }
            for l, v in sorted(by_lang.items())
        },
        "median_ms_best": round(msmed, 1) if allms else None,
    }


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("results")
    ap.add_argument("--label", default=None)
    ap.add_argument("--json", action="store_true", help="emit summary JSON")
    a = ap.parse_args()
    summ = score(a.results, a.label or a.results)
    if a.json:
        json.dump(summ, sys.stdout, ensure_ascii=False, indent=2)
        print()
