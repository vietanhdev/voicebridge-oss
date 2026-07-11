# ---------------------------------------------------------------------
# Copyright (c) 2026 Qualcomm Technologies, Inc. and/or its subsidiaries.
# SPDX-License-Identifier: BSD-3-Clause
# Modified by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
# ---------------------------------------------------------------------
"""Unit tests for PP-OCRv5 detection and recognition models."""
from __future__ import annotations

import numpy as np
import pytest

from qai_hub_models.models.pp_ocrv5.model import (
    MODEL_ID,
    MODEL_ASSET_VERSION,
    PPOCRv5Det,
    PPOCRv5Rec,
    PPOCRv5,
)
from qai_hub_models.scorecard.utils.testing import skip_clone_repo_check


@skip_clone_repo_check
def test_det_output_shape() -> None:
    """Detection model produces a probability map with the expected shape."""
    model = PPOCRv5Det.from_pretrained()
    img = np.random.rand(1, 3, 640, 640).astype("float32")
    prob_map = model(img)
    assert prob_map.shape == (1, 1, 640, 640), f"unexpected shape {prob_map.shape}"
    assert prob_map.dtype == np.float32
    # Probability map values should be in (0,1) after sigmoid
    assert prob_map.min() >= 0.0
    assert prob_map.max() <= 1.0


@skip_clone_repo_check
def test_zh_rec_output_shape() -> None:
    """ZH recognition model produces CTC logits with the expected vocab size."""
    model = PPOCRv5Rec.from_pretrained("zh")
    crop = np.random.rand(1, 3, 48, 320).astype("float32")
    logits = model(crop)
    # shape: [1, T, vocab]; vocab = 18383 chars + blank + space = 18385
    assert logits.ndim == 3, f"expected 3D output, got {logits.ndim}D"
    assert logits.shape[0] == 1
    assert logits.shape[2] == 18385, f"unexpected vocab size {logits.shape[2]}"


@skip_clone_repo_check
def test_ko_rec_output_shape() -> None:
    """KO recognition model produces CTC logits with the expected vocab size."""
    model = PPOCRv5Rec.from_pretrained("ko")
    crop = np.random.rand(1, 3, 48, 320).astype("float32")
    logits = model(crop)
    # shape: [1, T, vocab]; vocab = 11945 chars + blank + space = 11947
    assert logits.ndim == 3
    assert logits.shape[2] == 11947, f"unexpected vocab size {logits.shape[2]}"


@skip_clone_repo_check
def test_collection_from_pretrained() -> None:
    """CollectionModel loads all three components without error."""
    m = PPOCRv5.from_pretrained()
    assert m.det is not None
    assert m.zh_rec is not None
    assert m.ko_rec is not None


@skip_clone_repo_check
def test_det_non_zero_response() -> None:
    """Detection model responds to a high-contrast image (not all-zero output)."""
    model = PPOCRv5Det.from_pretrained()
    # White image with a centered black rectangle — simulates text on a sign
    img = np.ones((1, 3, 640, 640), dtype=np.float32)
    img[:, :, 200:440, 100:540] = 0.0  # dark rectangle
    prob_map = model(img)
    # The high-contrast region should activate some detection neurons
    assert prob_map.max() > 0.01, "detection model produced all-near-zero output"


@skip_clone_repo_check
def test_demo_runs() -> None:
    """demo.py main() completes without errors on synthetic input."""
    from qai_hub_models.models.pp_ocrv5.demo import main
    main()  # no image_path → runs on synthetic input
