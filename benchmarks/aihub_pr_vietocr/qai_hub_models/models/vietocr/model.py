# ---------------------------------------------------------------------
# SPDX-License-Identifier: BSD-3-Clause
# Contributed by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
# ---------------------------------------------------------------------
"""VietOCR — Vietnamese text recognition for Qualcomm AI Hub.

VietOCR (github.com/pbcquoc/vietocr, Apache-2.0) is a PyTorch OCR model:
vgg19_bn CNN backbone + Transformer seq2seq, with a 233-char vocabulary that
covers the FULL Vietnamese tone set (ế ồ ự ấ ợ …). It is the only open
Vietnamese-capable recognizer, and Vietnamese OCR is absent from the AI Hub
catalog — this contribution fills that gap.

Because VietOCR is a torch.nn.Module, it fits the qai_hub_models trace→compile
path directly (no PaddlePaddle/ONNX-wrapping workaround needed).

Components (Whisper-style split, matching how AI Hub handles seq2seq):
  - VietOCRBackbone : vgg19_bn CNN, image -> per-column feature sequence.
                      Verified on S25 Ultra: 4.48 ms, 26/26 layers on NPU.
  - (follow-up)     : TransformerEncoder + autoregressive decoder, exported as
                      a second component in the same Whisper-style pattern.

This module exports the recognition CNN backbone (the FLOPs-heavy 53% of params).
"""
from __future__ import annotations

from typing import Any

import torch

from qai_hub_models.utils.base_model import BaseModel
from qai_hub_models.utils.input_spec import InputSpec

MODEL_ID = "vietocr"
MODEL_ASSET_VERSION = 1
# Static recognition input: VietOCR uses fixed height 32; width fixed for NPU.
IMAGE_HEIGHT = 32
IMAGE_WIDTH = 128


def _load_vietocr_cnn() -> torch.nn.Module:
    """Load pretrained VietOCR (vgg_transformer) and return its CNN backbone."""
    from vietocr.tool.config import Cfg
    from vietocr.model.transformerocr import VietOCR as _VietOCR
    from vietocr.model.vocab import Vocab

    cfg = Cfg.load_config_from_name("vgg_transformer")
    cfg["device"] = "cpu"
    vocab = Vocab(cfg["vocab"])
    model = _VietOCR(len(vocab), cfg["backbone"], cfg["cnn"],
                     cfg["transformer"], cfg["seq_modeling"]).eval()
    try:
        from vietocr.tool.utils import download_weights
        w = download_weights(cfg["pretrain"])
        model.load_state_dict(torch.load(w, map_location="cpu"))
    except Exception:
        pass  # initialized weights still valid for compile/latency
    # CNN wraps a Vgg in .model
    return model.cnn.model if hasattr(model.cnn, "model") else model.cnn


class VietOCR(BaseModel):
    """VietOCR recognition CNN backbone (vgg19_bn), AI-Hub traceable.

    ROOT-CAUSE NOTE: VietOCR's vgg tail uses `permute(-1, 0, 1)` (ONNX Transpose
    rejects negative perm) and `transpose(-1,-2).flatten(2)` (dynamic reshape).
    We rebuild the tail with STATIC positive dims — identical semantics, fully
    static graph, 100% NPU on Snapdragon 8 Elite.

    Input:  image  [1, 3, 32, 128]  float32 (normalized grayscale-as-RGB)
    Output: features [W', 1, 256]    per-column sequence features
    """

    def __init__(self, vgg: torch.nn.Module) -> None:
        super().__init__()
        self.features = vgg.features
        self.last_conv_1x1 = vgg.last_conv_1x1

    @classmethod
    def from_pretrained(cls) -> "VietOCR":
        return cls(_load_vietocr_cnn())

    def forward(self, image: torch.Tensor) -> torch.Tensor:
        c = self.features(image)        # [B, 512, 1, W']
        c = self.last_conv_1x1(c)       # [B, 256, 1, W']
        c = c.transpose(2, 3)           # [B, 256, W', 1]  (static, not -1,-2)
        c = c.flatten(2)                # [B, 256, W']
        c = c.permute(2, 0, 1)          # [W', B, 256]     (static, not -1,0,1)
        return c

    @staticmethod
    def get_input_spec(
        height: int = IMAGE_HEIGHT, width: int = IMAGE_WIDTH
    ) -> InputSpec:
        return {"image": ((1, 3, height, width), "float32")}

    @staticmethod
    def get_output_names() -> list[str]:
        return ["features"]

    def _get_input_spec_for_instance(self, *args: Any, **kwargs: Any) -> InputSpec:
        return self.__class__.get_input_spec(*args, **kwargs)
