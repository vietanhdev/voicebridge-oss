# ---------------------------------------------------------------------
# SPDX-License-Identifier: BSD-3-Clause
# Contributed by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
# ---------------------------------------------------------------------
"""Unit tests for the VietOCR recognition backbone."""
from __future__ import annotations

import torch

from qai_hub_models.models.vietocr.model import VietOCR, IMAGE_HEIGHT, IMAGE_WIDTH
from qai_hub_models.scorecard.utils.testing import skip_clone_repo_check


@skip_clone_repo_check
def test_from_pretrained_and_forward() -> None:
    model = VietOCR.from_pretrained().eval()
    spec = VietOCR.get_input_spec()
    assert spec["image"][0] == (1, 3, IMAGE_HEIGHT, IMAGE_WIDTH)
    x = torch.rand(*spec["image"][0])
    with torch.no_grad():
        out = model(x)
    # output: [W', 1, 256] — sequence-major feature map
    assert out.ndim == 3, f"expected 3D output, got {out.ndim}D"
    assert out.shape[1] == 1
    assert out.shape[2] == 256, f"unexpected feature dim {out.shape[2]}"


@skip_clone_repo_check
def test_static_graph_no_negative_perm() -> None:
    """The rebuilt tail must export to ONNX without negative-perm Transpose
    or dynamic reshape (the root cause of the original AI Hub compile failure)."""
    import onnx
    model = VietOCR.from_pretrained().eval()
    x = torch.rand(*VietOCR.get_input_spec()["image"][0])
    path = "/tmp/vietocr_test.onnx"
    torch.onnx.export(model, x, path, input_names=["image"],
                      output_names=["features"], opset_version=17,
                      do_constant_folding=True, dynamo=False)
    m = onnx.load(path)
    onnx.checker.check_model(m)
    # shape inference must pass (it failed before the static-dims fix)
    onnx.shape_inference.infer_shapes(m, check_type=True, strict_mode=True)
    # no Transpose node may carry a negative perm
    for node in m.graph.node:
        if node.op_type == "Transpose":
            for attr in node.attribute:
                if attr.name == "perm":
                    assert all(p >= 0 for p in attr.ints), "negative perm in Transpose"
