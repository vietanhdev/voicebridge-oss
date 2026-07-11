# SPDX-License-Identifier: BSD-3-Clause
# Modified by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""Demo: run PP-OCRv5 det + ZH rec on a sample safety-sign image."""
from __future__ import annotations

import sys
from pathlib import Path

import cv2
import numpy as np

from .model import PPOCRv5Det, PPOCRv5Rec


def preprocess_det(img_bgr: np.ndarray, size: int = 640) -> np.ndarray:
    img = cv2.resize(img_bgr, (size, size)).astype("float32") / 255.0
    img = (img - np.array([0.485, 0.456, 0.406])) / np.array([0.229, 0.224, 0.225])
    return img.transpose(2, 0, 1)[np.newaxis].astype("float32")


def main(image_path: str | None = None) -> None:
    det = PPOCRv5Det.from_pretrained()
    rec = PPOCRv5Rec.from_pretrained("zh")

    if image_path is None:
        # synthetic white image with a black rectangle (dummy sign)
        img = np.ones((640, 640, 3), dtype=np.uint8) * 240
        cv2.putText(img, "注意安全", (100, 320), cv2.FONT_HERSHEY_SIMPLEX, 5, (0, 0, 0), 10)
    else:
        img = cv2.imread(image_path)
        if img is None:
            raise FileNotFoundError(image_path)

    det_input = preprocess_det(img)
    prob_map = det(det_input)
    print(f"det output shape: {prob_map.shape}  max: {prob_map.max():.3f}")

    # dummy rec run on a 320-wide crop
    crop = cv2.resize(img, (320, 48)).astype("float32") / 255.0
    crop = crop.transpose(2, 0, 1)[np.newaxis].astype("float32")
    logits = rec(crop)
    print(f"rec output shape: {logits.shape}")
    print("Demo complete.")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else None)
