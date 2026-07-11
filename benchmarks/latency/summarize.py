#!/usr/bin/env python3
"""Aggregate the on-device Whisper latency benchmark into a markdown table.

The app's `whisperLatencyBenchmark()` (long-press the Settings on-device-speech
tile) writes `whisper_latency.json` to the app documents dir. Pull it off the
device and summarise it here:

    adb exec-out run-as com.nrl.voicebridge cat \
        app_flutter/whisper_latency.json > whisper_latency.json   # path varies
    # or: adb pull <documents>/whisper_latency.json .
    python3 summarize.py whisper_latency.json

Reports per-language and overall best/median of the per-clip numbers. It only
summarises measured values — it never invents a number. Latency is wall-clock
`transcribeWav` (worker-isolate IPC + sherpa decode), warmup-excluded,
best-of-N per clip as recorded by the app.
"""
import json
import statistics
import sys


def med(xs):
    return statistics.median(xs) if xs else float("nan")


def main(path):
    with open(path, encoding="utf-8") as f:
        data = json.load(f)
    results = data.get("results", [])
    if not results:
        print(f"no results in {path}")
        return 1

    print(f"# Whisper STT latency — {path}\n")
    print(f"- engine: `{data.get('engine', 'unknown')}`")
    print(f"- protocol: {data.get('protocol', 'unknown')}")
    print(f"- clips: {len(results)}\n")

    by_lang = {}
    for r in results:
        by_lang.setdefault(r["lang"], []).append(r)

    print("| lang | clips | best ms (min) | median ms (median of per-clip medians) |")
    print("|------|-------|---------------|-----------------------------------------|")
    for lang in sorted(by_lang):
        rs = by_lang[lang]
        best = min(r["ms_best"] for r in rs)
        median = med([r["ms_median"] for r in rs])
        print(f"| {lang} | {len(rs)} | {best:.1f} | {median:.1f} |")
    allr = results
    print(
        f"| **all** | {len(allr)} | "
        f"{min(r['ms_best'] for r in allr):.1f} | "
        f"{med([r['ms_median'] for r in allr]):.1f} |"
    )
    return 0


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: python3 summarize.py whisper_latency.json")
        sys.exit(2)
    sys.exit(main(sys.argv[1]))
