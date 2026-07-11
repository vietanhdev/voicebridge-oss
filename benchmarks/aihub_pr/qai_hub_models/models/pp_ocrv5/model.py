# ---------------------------------------------------------------------
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
# Modified by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
# ---------------------------------------------------------------------
"""PP-OCRv5 detection + ZH/KO recognition models (Chinese + Korean).

Three components:
  - det:    PP-OCRv5 mobile text detection (PP-HGNetV2 + DB++ head + DSR)
  - zh_rec: PP-OCRv5 server recognition for Simplified Chinese + English
  - ko_rec: PP-OCRv5 mobile recognition for Korean + English

Source: PaddleOCR 3.x (Apache-2.0), ONNX exports from monkt/paddleocr-onnx.
"""

from __future__ import annotations

from typing import List, Tuple

import numpy as np
import onnxruntime as ort
from qai_hub_models.utils.base_model import BaseModel, CollectionModel, TargetRuntime

MODEL_ID = "pp_ocrv5"
MODEL_ASSET_VERSION = 1

# HuggingFace-hosted ONNX exports (Apache-2.0, no pickle)
_HF_BASE = "https://huggingface.co/monkt/paddleocr-onnx/resolve/main"
_DET_URL = f"{_HF_BASE}/detection/v3/det.onnx"
_ZH_REC_URL = f"{_HF_BASE}/languages/chinese/rec.onnx"
_KO_REC_URL = f"{_HF_BASE}/languages/korean/rec.onnx"


class PPOCRv5Det(BaseModel):
    """PP-OCRv5 mobile text detection (DB++ head).

    Input:  image  [1, 3, 640, 640]  float32, normalized [0,1]
    Output: prob_map [1, 1, 640, 640]  float32, sigmoid probability

    Example:
        >>> import numpy as np
        >>> model = PPOCRv5Det.from_pretrained()
        >>> img = np.random.rand(1, 3, 640, 640).astype("float32")
        >>> prob_map = model(img)
    """

    def __init__(self, model: ort.InferenceSession) -> None:
        self._sess = model

    @classmethod
    def from_pretrained(cls) -> PPOCRv5Det:
        from qai_hub_models.utils.asset_loaders import CachedWebModelAsset
        asset = CachedWebModelAsset.from_url(_DET_URL, MODEL_ID, MODEL_ASSET_VERSION, "det.onnx")
        sess = ort.InferenceSession(asset.fetch(), providers=["CPUExecutionProvider"])
        return cls(sess)

    def forward(self, image: np.ndarray) -> np.ndarray:
        name = self._sess.get_inputs()[0].name
        return self._sess.run(None, {name: image})[0]

    @staticmethod
    def get_input_spec() -> dict:
        return {"image": ((1, 3, 640, 640), "float32")}

    @staticmethod
    def get_output_names() -> List[str]:
        return ["prob_map"]

    @staticmethod
    def get_channel_last_inputs() -> List[str]:
        return []

    @staticmethod
    def get_channel_last_outputs() -> List[str]:
        return []

    @classmethod
    def from_source_model(cls) -> PPOCRv5Det:
        return cls.from_pretrained()


class PPOCRv5Rec(BaseModel):
    """PP-OCRv5 text recognition (SVTR/CTC).

    Input:  image  [1, 3, 48, W]  float32, normalized [0,1]
    Output: logits [1, T, vocab]  float32 (CTC outputs)

    Example:
        >>> import numpy as np
        >>> model = PPOCRv5Rec.from_pretrained("zh")
        >>> crop = np.random.rand(1, 3, 48, 320).astype("float32")
        >>> logits = model(crop)
    """

    def __init__(self, model: ort.InferenceSession) -> None:
        self._sess = model

    @classmethod
    def from_pretrained(cls, lang: str = "zh") -> PPOCRv5Rec:
        from qai_hub_models.utils.asset_loaders import CachedWebModelAsset
        url = _ZH_REC_URL if lang == "zh" else _KO_REC_URL
        asset = CachedWebModelAsset.from_url(url, MODEL_ID, MODEL_ASSET_VERSION, f"{lang}_rec.onnx")
        sess = ort.InferenceSession(asset.fetch(), providers=["CPUExecutionProvider"])
        return cls(sess)

    def forward(self, image: np.ndarray) -> np.ndarray:
        name = self._sess.get_inputs()[0].name
        return self._sess.run(None, {name: image})[0]

    @staticmethod
    def get_input_spec() -> dict:
        return {"image": ((1, 3, 48, 320), "float32")}

    @staticmethod
    def get_output_names() -> List[str]:
        return ["logits"]

    @staticmethod
    def get_channel_last_inputs() -> List[str]:
        return []

    @staticmethod
    def get_channel_last_outputs() -> List[str]:
        return []

    @classmethod
    def from_source_model(cls) -> PPOCRv5Rec:
        return cls.from_pretrained()


class PPOCRv5(CollectionModel):
    """Combined PP-OCRv5 det + zh_rec + ko_rec for Chinese/Korean signage OCR.

    Usage:
        det    = PPOCRv5Det   → submits as 'det'    component
        zh_rec = PPOCRv5Rec   → submits as 'zh_rec' component
        ko_rec = PPOCRv5Rec   → submits as 'ko_rec' component
    """

    def __init__(
        self,
        det: PPOCRv5Det,
        zh_rec: PPOCRv5Rec,
        ko_rec: PPOCRv5Rec,
    ) -> None:
        self.det = det
        self.zh_rec = zh_rec
        self.ko_rec = ko_rec

    @classmethod
    def from_pretrained(cls) -> PPOCRv5:
        return cls(
            det=PPOCRv5Det.from_pretrained(),
            zh_rec=PPOCRv5Rec.from_pretrained("zh"),
            ko_rec=PPOCRv5Rec.from_pretrained("ko"),
        )
