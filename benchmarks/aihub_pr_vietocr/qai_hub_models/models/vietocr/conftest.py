# ---------------------------------------------------------------------
# SPDX-License-Identifier: BSD-3-Clause
# Contributed by: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
# ---------------------------------------------------------------------
import gc
import warnings

import pytest

from qai_hub_models.models.vietocr.model import VietOCR
from qai_hub_models.scorecard.utils.testing import make_cached_from_pretrained_fixture


def pytest_configure(config: pytest.Config) -> None:
    try:
        import torch.jit._trace
        warnings.filterwarnings(action="ignore", category=torch.jit._trace.TracerWarning)
        warnings.filterwarnings(action="ignore", category=UserWarning, module="torch.*")
    except ImportError:
        pass


cached_from_pretrained = make_cached_from_pretrained_fixture(VietOCR, skip_clone_repo=True)


@pytest.fixture(scope="module", autouse=True)
def ensure_gc() -> None:
    gc.collect()
