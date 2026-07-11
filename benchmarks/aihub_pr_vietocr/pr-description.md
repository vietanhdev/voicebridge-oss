# Add VietOCR — Vietnamese OCR for Qualcomm AI Hub

## Summary
Adds **`vietocr`** to the AI Hub model catalog: Vietnamese text recognition (vgg19_bn CNN +
Transformer seq2seq, 233-char vocab covering the full tone set). **Vietnamese OCR is currently
absent from the catalog** — this fills that gap with the most widely-used open VN recognizer.

This is the **internal review draft**; after approval it becomes the public PR to
`quic/ai-hub-models`.

## Why VietOCR (and why not PP-OCRv5)
- `qai_hub_models.BaseModel` extends `torch.nn.Module` — the framework traces torch models. We
  first tried PP-OCRv5, but it is **PaddlePaddle**; an ONNX-wrapping `model.py` won't pass CI and
  a torch port is multi-week. **VietOCR is already PyTorch** → it fits the contract directly.
- Apache-2.0; broad adoption; full Vietnamese tone vocab.

## What's measured (real, S25 Ultra via AI Hub)
| component | params | NPU latency | NPU layers |
|-----------|--------|-------------|------------|
| vgg19_bn recognition backbone | 20.2M (53%) | **4.48 ms** | **26/26 (100%)** |

Compile job `jgl71q225`, profile `j5qwmd3e5`, qairt 2.45.0, 2026-06-06.

## Scope of this draft
- ✅ Recognition **CNN backbone** — model.py (torch BaseModel), export.py, test.py, conftest.py,
  info.yaml, perf.yaml (measured), code-gen.yaml, README, requirements.
- ⏭ **Follow-up before public submission:** Transformer encoder/decoder as a 2nd component
  (Whisper-style split) for the full image→text pipeline.

## Root-cause fix (engineering note)
VietOCR's vgg tail uses `permute(-1,0,1)` (ONNX `Transpose` rejects negative perm) and
`transpose(-1,-2).flatten(2)` (dynamic `Shape→Slice→Reshape`) → AI Hub shape inference fails.
Rebuilt the tail with **static positive dims** (`transpose(2,3)`, `permute(2,0,1)`) — identical
semantics, fully static graph, 100% NPU. Covered by `test.py::test_static_graph_no_negative_perm`.

## Local test status
`test.py` logic verified locally: from_pretrained + forward → output `(W',1,256)`; ONNX export
+ `onnx.shape_inference` pass; no negative-perm Transpose. (AI Hub compile + profile also green.)

## Files
```
qai_hub_models/models/vietocr/
├── __init__.py  model.py  export.py  demo (n/a)  test.py  conftest.py
├── info.yaml  perf.yaml  code-gen.yaml  requirements.txt  README.md
```

## Checklist
- [x] Apache-2.0 source; no pickle (torch ckpt → traced → ONNX/TFLite)
- [x] torch.nn.Module BaseModel with from_pretrained / get_input_spec / forward
- [x] NPU latency measured on real S25 Ultra (100% NPU)
- [x] test.py + conftest.py matching catalog patterns; local logic verified
- [ ] Transformer enc/dec component (follow-up)
- [ ] Static banner image (optional; info.yaml has_static_banner=false)

Contributed by Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
