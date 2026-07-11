#!/usr/bin/env python3
"""Compile PP-OCRv5 ONNX models for Snapdragon 8 Elite via Qualcomm AI Hub.

Produces:
  out/pp_ocrv5_det_mobile.tflite   -- 2.4 MB mobile det
  out/pp_ocrv5_zh_rec.tflite       -- ZH server rec (swap for mobile rec when available)
  out/pp_ocrv5_ko_rec.tflite       -- KO mobile rec
  out/pp_ocrv5_lat_rec.tflite      -- Latin mobile rec (benchmark only; not for VN)
  out/<model>_profile.json         -- on-cloud latency on a real S25 device

Requires:
  pip install "qai-hub"
  qai-hub configure --api_token YOUR_TOKEN
  (get token: workbench.aihub.qualcomm.com -> Account -> Settings -> API Token)

Models (Apache-2.0, from monkt/paddleocr-onnx on HuggingFace — not committed):
  /tmp/ppv5/det/det_v3.onnx   2.4 MB   PP-OCRv5 mobile det
  /tmp/ppv5/zh/rec.onnx       81  MB   PP-OCRv5 ZH server rec (float32)
  /tmp/ppv5/ko/rec.onnx       13  MB   PP-OCRv5 KO mobile rec
  /tmp/ppv5/latin/rec.onnx     7.6 MB  PP-OCRv5 Latin mobile rec

QUANTIZATION NOTE (no fabricated numbers):
  PP-OCRv5 ONNX exports are float32. HTP NPU requires int8/int16 QDQ to run on-chip.
  This script passes a small calibration dataset so AI Hub runs PTQ in-cloud.
  If any model falls back fully to CPU (check profile.json 'num_delegated_layers'),
  re-run with larger calibration_data or pre-quantize with AIMET offline.
  Do NOT report NPU latency as confirmed until profile shows ops delegated to HTP.

Device choice:
  "Samsung Galaxy S25 (Family)" -> any S25 unit (S25/S25+/S25 Ultra), SM8750.
  Recommended for TFLite jobs — shorter queue, same SoC as our test device.

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import json
import os
import time
from pathlib import Path

import numpy as np
import qai_hub as hub

# ---------------------------------------------------------------------------
HERE = Path(__file__).parent
OUT = HERE / "out"
OUT.mkdir(exist_ok=True)

DEVICE = "Samsung Galaxy S25 (Family)"

# Input specs: fixed shapes (HTP requires static dims)
MODELS = {
    "pp_ocrv5_det_mobile": {
        "path": "/tmp/ppv5/det/det_v3.onnx",
        "input_specs": {"x": (1, 3, 640, 640)},
    },
    "pp_ocrv5_zh_rec": {
        "path": "/tmp/ppv5/zh/rec.onnx",
        "input_specs": {"x": (1, 3, 48, 320)},  # fixed-width slice for calibration
    },
    "pp_ocrv5_ko_rec": {
        "path": "/tmp/ppv5/ko/rec.onnx",
        "input_specs": {"x": (1, 3, 48, 320)},
    },
    "pp_ocrv5_lat_rec": {
        "path": "/tmp/ppv5/latin/rec.onnx",
        "input_specs": {"x": (1, 3, 48, 320)},
    },
}


def make_calib(input_specs: dict, n: int = 100) -> dict[str, list[np.ndarray]]:
    """Generate n random float32 calibration samples (uniform [0,1]) for PTQ.
    Real sign images would give tighter quantization; random is a baseline."""
    calib = {}
    for name, shape in input_specs.items():
        calib[name] = [np.random.rand(*shape).astype("float32") for _ in range(n)]
    return calib


def compile_model(name: str, cfg: dict) -> tuple[hub.CompileJob, str]:
    """Submit a TFLite compile job with in-cloud PTQ calibration."""
    print(f"\n[{name}] submitting compile job -> {DEVICE}")
    calib = make_calib(cfg["input_specs"])
    job = hub.submit_compile_job(
        model=cfg["path"],
        device=hub.Device(DEVICE),
        name=name,
        input_specs=cfg["input_specs"],
        options="--target_runtime tflite",
        calibration_data=calib,
    )
    print(f"[{name}] job id: {job.job_id}  status: {job.get_status().symbol}")
    return job, name


def profile_model(name: str, tflite_model: hub.Model) -> hub.ProfileJob:
    """Profile the compiled .tflite on a real cloud S25 device."""
    print(f"[{name}] submitting profile job")
    return hub.submit_profile_job(
        model=tflite_model,
        device=hub.Device(DEVICE),
        name=f"{name}_profile",
    )


def wait_and_download(job: hub.CompileJob, name: str) -> hub.Model | None:
    """Wait for compile job, download .tflite, return Hub model handle."""
    print(f"[{name}] waiting...", end="", flush=True)
    while True:
        status = job.get_status()
        print(f"\r[{name}] {status.symbol} {status.message:<40}", end="", flush=True)
        if job.finished:
            break
        time.sleep(10)
    print()
    if job.successful:
        out_path = str(OUT / f"{name}.tflite")
        job.download_target_model(out_path)
        size_kb = os.path.getsize(out_path) // 1024
        print(f"[{name}] downloaded -> {out_path} ({size_kb} KB)")
        return job.get_target_model()
    else:
        print(f"[{name}] FAILED: {job.get_status().message}")
        return None


def wait_profile(job: hub.ProfileJob, name: str) -> None:
    print(f"[{name}_profile] waiting...", end="", flush=True)
    while True:
        status = job.get_status()
        print(f"\r[{name}_profile] {status.symbol} {status.message:<40}", end="", flush=True)
        if job.finished:
            break
        time.sleep(10)
    print()
    if job.successful:
        out_path = str(OUT / f"{name}_profile.json")
        job.download_profile_data(out_path)
        # parse and surface the key numbers
        data = json.load(open(out_path))
        layers = data.get("execution_detail", {}).get("layers", [])
        total_ms = data.get("execution_summary", {}).get("estimated_inference_time_ms")
        delegated = sum(1 for l in layers if "htp" in l.get("delegate", "").lower())
        print(f"[{name}_profile] total {total_ms} ms | {delegated}/{len(layers)} layers on HTP")
        # Warn if NPU delegation is low
        if layers and delegated < len(layers) * 0.8:
            print(f"  *** WARNING: only {delegated}/{len(layers)} layers on HTP. "
                  "Model may be running mostly on CPU. Consider offline quantization. ***")
    else:
        print(f"[{name}_profile] FAILED: {job.get_status().message}")


def main():
    # Verify auth before doing anything
    try:
        hub.get_devices()
    except hub.client.exceptions.UserAuthenticationException:
        print("ERROR: not authenticated. Run:")
        print("  qai-hub configure --api_token YOUR_TOKEN")
        print("  (get token: workbench.aihub.qualcomm.com -> Account -> Settings -> API Token)")
        raise SystemExit(1)

    print(f"Compiling {len(MODELS)} models for '{DEVICE}'")
    print(f"Output dir: {OUT}\n")

    # Submit all compile jobs in parallel (don't wait between submissions)
    jobs: list[tuple[hub.CompileJob, str]] = []
    for name, cfg in MODELS.items():
        if not Path(cfg["path"]).exists():
            print(f"[{name}] SKIP — model not found: {cfg['path']}")
            continue
        jobs.append(compile_model(name, cfg))

    # Wait + download, then immediately submit profile jobs
    profile_jobs: list[tuple[hub.ProfileJob, str]] = []
    for job, name in jobs:
        model = wait_and_download(job, name)
        if model:
            pjob = profile_model(name, model)
            profile_jobs.append((pjob, name))

    # Wait for all profiles
    for pjob, name in profile_jobs:
        wait_profile(pjob, name)

    print("\n=== Summary ===")
    for name in MODELS:
        tflite = OUT / f"{name}.tflite"
        profile = OUT / f"{name}_profile.json"
        tflite_ok = "✓" if tflite.exists() else "✗"
        profile_ok = "✓" if profile.exists() else "✗"
        print(f"  {tflite_ok} {name}.tflite   {profile_ok} _profile.json")

    print(f"\nNext steps:")
    print(f"  1. Check profile JSON: num_delegated_layers / total -> confirm HTP offload")
    print(f"  2. Copy .tflite to android/app/src/main/assets/models/")
    print(f"  3. Add LiteRT + QNN delegate to build.gradle, write MethodChannel bridge")
    print(f"  4. Update benchmarks/ocr/README.md with real on-device NPU latency numbers")


if __name__ == "__main__":
    main()
