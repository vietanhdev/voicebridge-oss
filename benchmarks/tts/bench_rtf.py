#!/usr/bin/env python3
"""Supertonic-3 TTS real-time-factor (RTF) benchmark — CPU, on-device-representative.

Model:   Supertone/supertonic-3 (ONNX, ~99M params), via the `supertonic` PyPI pkg.
  License:  code MIT, weights OpenRAIL-M (commercial-OK, use-restrictions + attribution).
  Format:  ONNX only — no pickle / torch (dependency audit per project policy: reject opaque/pickled artifacts).
  Langs:   VN · KO · EN (+ 27 more); NOT Chinese — ZH routes to MeloTTS-ZH in the app.

Metric:  RTF = synthesis_wall_time / generated_audio_seconds. Lower is faster; RTF<1
         means faster than real time. We report the BEST-OF-N (min) and MEDIAN over N
         timed runs per sentence, AFTER warmup, per the project benchmark policy:
           - warm up `--warmup` calls (ONNX session + first-run graph opt) before timing
           - time `--reps` runs, report median + best (single-run numbers are noise)
           - pin package + onnxruntime versions and the bench date in the output JSON
         CPU RTF is platform-honest and transfers conservatively to the S25 NPU/GPU
         (ONNX Runtime), where it can only get faster — never reported as the NPU number.

Usage:   python3 bench_rtf.py --langs vi en ko --reps 5 --warmup 3

Author:  Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import argparse
import json
import platform
import statistics
import time
from pathlib import Path

HERE = Path(__file__).parent

# Representative phrases (~1 conversational sentence each) per language. Held in-repo so
# the bench is reproducible from a clean clone (no external corpus download for timing).
SENTENCES = {
    "vi": "Xin chào, tôi cần trợ giúp dịch thuật tại nhà máy này.",
    "en": "Hello, I need help translating at this factory today.",
    "ko": "안녕하세요, 오늘 이 공장에서 통역 도움이 필요합니다.",
}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--langs", nargs="+", default=["vi", "en", "ko"])
    ap.add_argument("--reps", type=int, default=5)
    ap.add_argument("--warmup", type=int, default=3)
    ap.add_argument("--threads", type=int, default=4, help="intra-op threads (S25=8 big cores)")
    a = ap.parse_args()

    import numpy as np
    import onnxruntime
    import supertonic as s

    tts = s.TTS(model="supertonic-3", intra_op_num_threads=a.threads)
    model_dir = s.loader.get_model_cache_dir("supertonic-3")
    voices = sorted(s.loader.list_available_voice_style_names(model_dir))
    voice = voices[0]
    style = tts.get_voice_style(voice)
    sr = 44100  # Supertonic-3 outputs 44.1 kHz

    results = {}
    for lang in a.langs:
        text = SENTENCES[lang]
        # warmup (not timed) — first call builds the ORT graph + caches
        for _ in range(a.warmup):
            tts.synthesize(text, style, lang=lang)
        rtfs, audio_s = [], None
        for _ in range(a.reps):
            t0 = time.perf_counter()
            audio, _ = tts.synthesize(text, style, lang=lang)
            dt = time.perf_counter() - t0
            audio_s = len(np.asarray(audio).reshape(-1)) / sr
            rtfs.append(dt / audio_s)
        results[lang] = {
            "rtf_best": round(min(rtfs), 4),
            "rtf_median": round(statistics.median(rtfs), 4),
            "audio_s": round(audio_s, 3),
            "reps": a.reps,
        }
        print(f"=== {lang}: RTF best={min(rtfs):.3f} median={statistics.median(rtfs):.3f} "
              f"({audio_s:.2f}s audio, {a.reps} reps) ===", flush=True)

    out = HERE / "results_supertonic3_rtf.json"
    out.write_text(json.dumps({
        "model": "Supertone/supertonic-3 (ONNX, ~99M params)",
        "package": f"supertonic=={s.__version__}",
        "runtime": f"onnxruntime=={onnxruntime.__version__}",
        "provider": "CPUExecutionProvider",
        "voice": voice,
        "machine": f"{platform.processor() or platform.machine()} / {platform.system()}",
        "threads": a.threads,
        "protocol": f"warmup={a.warmup}, reps={a.reps}, RTF=synth_wall/audio_seconds, best+median",
        "license": "code MIT, weights OpenRAIL-M",
        "results": results,
    }, ensure_ascii=False, indent=2))
    print("wrote", out)


if __name__ == "__main__":
    main()
