# VietOCR — Vietnamese OCR for Qualcomm AI Hub

Vietnamese text recognition (vgg19_bn CNN + Transformer seq2seq, 233-char vocab with the
full tone set). **Vietnamese OCR is absent from the AI Hub catalog** — this fills that gap.

## Why this model

- **Only open Vietnamese-capable recognizer** with broad adoption (pbcquoc/vietocr).
- **PyTorch** → traces + compiles to the Snapdragon NPU via the standard AI Hub path.
- **Apache-2.0.**

## Performance (this contribution: recognition CNN backbone)

| component | params | device | NPU latency | NPU layers |
|-----------|--------|--------|-------------|------------|
| vgg19_bn backbone | 20.2M (53%) | Samsung Galaxy S25 Ultra | **4.48 ms** | **26/26 (100%)** |

Compile job `jgl71q225`, profile `j5qwmd3e5` (qairt 2.45.0, 2026-06-06). The Transformer
encoder/decoder (the remaining 47%) follows as a second component in the Whisper-style split.

## Engineering note (root-cause fix)

VietOCR's vgg tail uses `permute(-1, 0, 1)` — ONNX `Transpose` rejects **negative perm** — and
`transpose(-1,-2).flatten(2)`, which exports a dynamic `Shape→Slice→Reshape`. Both make AI Hub's
shape inference fail. We rebuild the tail with **static positive dims** (`transpose(2,3)`,
`permute(2,0,1)`) — identical semantics, fully static graph, 100% NPU. See `model.py` + `test.py`.

## Usage

```python
python3 -m qai_hub_models.models.vietocr.export --device "Samsung Galaxy S25 Ultra"
```

## License

VietOCR: Apache-2.0 (https://github.com/pbcquoc/vietocr). This contribution: BSD-3-Clause.
Contributed by Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
