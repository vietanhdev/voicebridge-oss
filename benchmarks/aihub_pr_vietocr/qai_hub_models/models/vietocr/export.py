# ---------------------------------------------------------------------
# SPDX-License-Identifier: BSD-3-Clause
# Contributed by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
# ---------------------------------------------------------------------
"""Export VietOCR recognition CNN backbone to Qualcomm AI Hub.

    python3 -m qai_hub_models.models.vietocr.export --device "Samsung Galaxy S25 Ultra"
"""
from __future__ import annotations

import argparse
import time
from pathlib import Path

import torch
import qai_hub as hub

from qai_hub_models.models.vietocr.model import VietOCR, MODEL_ID, IMAGE_HEIGHT, IMAGE_WIDTH


def export(device: str = "Samsung Galaxy S25 (Family)",
           target_runtime: str = "tflite",
           output_dir: str = "export_assets/vietocr",
           skip_profiling: bool = False) -> None:
    out = Path(output_dir)
    out.mkdir(parents=True, exist_ok=True)
    dev = hub.Device(device)

    model = VietOCR.from_pretrained().eval()
    spec = VietOCR.get_input_spec()
    example = torch.rand(*spec["image"][0])

    # Export ONNX with STATIC shapes + constant folding (avoids the negative-perm /
    # dynamic-reshape shape-inference failure in the auto trace->ONNX path).
    onnx_path = str(out / "vietocr_backbone.onnx")
    torch.onnx.export(model, example, onnx_path, input_names=["image"],
                      output_names=["features"], opset_version=17,
                      do_constant_folding=True, dynamo=False)
    import onnx
    onnx.save(onnx.shape_inference.infer_shapes(
        onnx.load(onnx_path), check_type=True, strict_mode=True), onnx_path)

    cj = hub.submit_compile_job(
        model=onnx_path, device=dev, name=f"{MODEL_ID}_backbone",
        input_specs=spec, options=f"--target_runtime {target_runtime}")
    while not cj.get_status().finished:
        time.sleep(15)
    assert cj.get_status().success, cj.get_status().message
    cj.download_target_model(str(out / f"{MODEL_ID}_backbone.{target_runtime}"))

    if not skip_profiling:
        pj = hub.submit_profile_job(model=cj.get_target_model(), device=dev,
                                    name=f"{MODEL_ID}_profile")
        while not pj.get_status().finished:
            time.sleep(15)
        if pj.get_status().success:
            import json
            pj.download_profile(str(out / f"{MODEL_ID}_profile.json"))
            d = json.load(open(out / f"{MODEL_ID}_profile.json"))
            ms = d["execution_summary"]["estimated_inference_time"] / 1000.0
            npu = sum(1 for l in d["execution_detail"] if l.get("compute_unit") == "NPU")
            print(f"{MODEL_ID}: {ms:.2f} ms | {npu}/{len(d['execution_detail'])} NPU")


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--device", default="Samsung Galaxy S25 (Family)")
    p.add_argument("--target-runtime", default="tflite",
                   choices=["tflite", "qnn_context_binary", "onnx"])
    p.add_argument("--output-dir", default="export_assets/vietocr")
    p.add_argument("--skip-profiling", action="store_true")
    a = p.parse_args()
    export(a.device, a.target_runtime, a.output_dir, a.skip_profiling)


if __name__ == "__main__":
    main()
