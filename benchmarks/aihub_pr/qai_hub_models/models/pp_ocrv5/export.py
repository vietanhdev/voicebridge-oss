# ---------------------------------------------------------------------
# SPDX-License-Identifier: BSD-3-Clause
# Modified by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
# ---------------------------------------------------------------------
"""Export PP-OCRv5 det + ZH/KO rec to Qualcomm AI Hub (int8 TFLite).

Usage:
    python3 -m qai_hub_models.models.pp_ocrv5.export \
        --device "Samsung Galaxy S25 Ultra" \
        --target-runtime tflite \
        --components det zh_rec ko_rec
"""
from __future__ import annotations

import argparse
from pathlib import Path
from typing import Optional

import numpy as np
import qai_hub as hub

from .model import PPOCRv5

DEVICE_DEFAULT = "Samsung Galaxy S25 (Family)"
RUNTIME_DEFAULT = "tflite"
OUTPUT_DIR_DEFAULT = Path("export_assets") / "pp_ocrv5"

COMPONENTS = {
    "det":    {"model_attr": "det",    "input_specs": {"x": (1, 3, 640, 640)}},
    "zh_rec": {"model_attr": "zh_rec", "input_specs": {"x": (1, 3, 48, 320)}},
    "ko_rec": {"model_attr": "ko_rec", "input_specs": {"x": (1, 3, 48, 320)}},
}


def _calib(specs: dict, n: int = 100) -> dict:
    return {k: [np.random.rand(*s).astype("float32") for _ in range(n)] for k, s in specs.items()}


def export(
    device: str = DEVICE_DEFAULT,
    target_runtime: str = RUNTIME_DEFAULT,
    components: list[str] | None = None,
    output_dir: Path = OUTPUT_DIR_DEFAULT,
    skip_profiling: bool = False,
    skip_downloading: bool = False,
) -> dict[str, hub.CompileJob]:
    """Compile each component to int8 TFLite via AI Hub PTQ and optionally profile."""
    if components is None:
        components = list(COMPONENTS.keys())
    output_dir = Path(output_dir)
    output_dir.mkdir(parents=True, exist_ok=True)

    dev = hub.Device(device)
    compile_jobs: dict[str, hub.CompileJob] = {}

    for comp in components:
        cfg = COMPONENTS[comp]
        print(f"[{comp}] submitting compile job...")
        job = hub.submit_compile_job(
            model=f"/tmp/ppv5/{'det/det_v3' if comp=='det' else comp.split('_')[0]+'/rec'}.onnx",
            device=dev,
            name=f"pp_ocrv5_{comp}",
            input_specs=cfg["input_specs"],
            options=f"--target_runtime {target_runtime} --quantize_full_type int8",
            calibration_data=_calib(cfg["input_specs"]),
        )
        compile_jobs[comp] = job
        print(f"[{comp}] job_id: {job.job_id}")

    # Wait + download
    for comp, job in compile_jobs.items():
        import time
        while not job.get_status().finished:
            time.sleep(15)
        s = job.get_status()
        if s.success:
            if not skip_downloading:
                out = str(output_dir / f"pp_ocrv5_{comp}.tflite")
                job.download_target_model(out)
                print(f"[{comp}] saved {out}")
            if not skip_profiling:
                pjob = hub.submit_profile_job(
                    model=job.get_target_model(), device=dev, name=f"pp_ocrv5_{comp}_profile"
                )
                while not pjob.get_status().finished:
                    time.sleep(15)
                if pjob.get_status().success:
                    import json
                    pout = str(output_dir / f"pp_ocrv5_{comp}_profile.json")
                    pjob.download_profile(pout)
                    d = json.load(open(pout))
                    ms = d["execution_summary"]["estimated_inference_time"] / 1000.0
                    layers = d["execution_detail"]
                    npu = sum(1 for l in layers if l.get("compute_unit") == "NPU")
                    print(f"[{comp}] {ms:.2f} ms | {npu}/{len(layers)} NPU")
        else:
            print(f"[{comp}] FAILED: {s.message}")

    return compile_jobs


def main() -> None:
    p = argparse.ArgumentParser(description="Export PP-OCRv5 to AI Hub")
    p.add_argument("--device", default=DEVICE_DEFAULT)
    p.add_argument("--target-runtime", default=RUNTIME_DEFAULT, choices=["tflite", "qnn_context_binary"])
    p.add_argument("--components", nargs="+", default=list(COMPONENTS.keys()),
                   choices=list(COMPONENTS.keys()))
    p.add_argument("--output-dir", default=str(OUTPUT_DIR_DEFAULT), type=Path)
    p.add_argument("--skip-profiling", action="store_true")
    p.add_argument("--skip-downloading", action="store_true")
    args = p.parse_args()
    export(
        device=args.device,
        target_runtime=args.target_runtime,
        components=args.components,
        output_dir=args.output_dir,
        skip_profiling=args.skip_profiling,
        skip_downloading=args.skip_downloading,
    )


if __name__ == "__main__":
    main()
