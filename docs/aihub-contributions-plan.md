# Qualcomm AI Hub — model contribution plan

Plan + status for contributing VoiceBridge-relevant models to
[qualcomm/ai-hub-models](https://github.com/qualcomm/ai-hub-models). Fork:
`vietanhdev/ai-hub-models`; internal review copy: `nrl-ai/ai-hub-models`. Every model
must compile/profile on AI Hub and follow upstream conventions (uniform copyright header,
schema-valid `info.yaml`, no `perf.yaml`/`release-assets.yaml` — the scorecard CI generates
those), with a permissive license and no fabricated numbers.

## Submitted (open PRs, Hub-validated)
| Model | PR | License | Hub result |
|-------|----|---------|-----------|
| PhoWhisper-Small (VN ASR) | qualcomm#322 | BSD-3 | enc 70.2 / dec 8.3 ms, 100% NPU, inference ✓ |
| VietOCR (VN OCR) | qualcomm#323 | Apache-2.0 | 4.5 ms, 100% NPU, PSNR 75.1 |
| PP-OCRv5 (det + 7 v5 recognizers) | qualcomm#324 | Apache-2.0 | det 1.54 / ko 4.39 / zh 10.84 ms float, 100% NPU |

PP-OCRv5 uses the ONNX-source `serialize()` pattern (like `pi05`) since PaddleOCR is not torch.
All three: 1 commit, signed-off (DCO), model-only diff.

## Planned — MT (LLM)
| Model | Params | License | Why | Status / blocker |
|-------|--------|---------|-----|------------------|
| **Gemma 4 E2B** | ~1.91B effective (PLE) | **Apache-2.0** | on-device multilingual MT; Gemma 4 dropped the custom Gemma Terms → now license-clean | benchmark VN↔EN/KO/ZH spBLEU (FLORES) before any claim; large generative export (like MADLAD) — heavy |
| **Gemma 4 E4B** | ~4B effective | **Apache-2.0** | higher-accuracy tablet tier | same; bigger download/trace |
| MADLAD-400-3B | 3B | Apache-2.0 | 400-lang MT, permissive | branch ready (`add-madlad400-3b`). **Local export probed:** translations verified correct (EN→VI/KO, VN→EN all good); **encoder ONNX exports**; the 3B **decoder** ONNX export is heavy (7 GB torchscript stage saved, but the legacy ONNX conversion is slow/memory-bound and didn't finish in-run + produces ~17 GB scratch). Completing it needs a longer run + the static-KV-cache decoder spec finished. |

> **Gemma version note:** Gemma **3n** E2B/E4B ship under the custom *Gemma Terms + Prohibited
> Use Policy* (NOT Apache) — those stay use-restricted. Gemma **4** E2B/E4B are **Apache-2.0**.
> Only the Gemma 4 line is a clean contribution/ship candidate. Any spBLEU for Gemma 4 must be
> freshly measured — the existing 32.81 figure was measured on a different Gemma checkpoint.

## Planned — TTS
| Model | License | Status / blocker |
|-------|---------|------------------|
| Kokoro (82M) | Apache-2.0 | branch ready (`add-kokoro`). **Local ONNX export NOW WORKS** (fixed: complex iSTFT → conv `CustomSTFT` via `disable_complex`, pack/pad LSTM → dense passthrough, int64 → `--truncate_64bit_tensors`; synthesized audio verified correct via Whisper round-trip). **NPU compile still blocked**: StyleTTS2 decoder output length = sum(predicted durations) is data-dependent; TFLite/QNN need static shapes, and a static-width rewrite breaks the audio (length-dependent InstanceNorm/source-gen). NPU-resident Kokoro needs a masked-decoder rewrite (multi-day). CPU/GPU on-device is fine. |
| Piper-VN (`vi_VN-vais1000-medium`) | CC-BY-4.0 (voice) | branch ready (`add-pipertts-vi`). **Hard-blocked:** the shared pipertts code imports `piper_train` (the Piper training repo's `vits`), which is **not on PyPI** (and `piper-phonemize` has no wheel here). Can't load → can't export without vendoring the Piper training source. |

## Next actions
1. **Gemma 4 E2B/E4B**: download (Apache), benchmark VN↔EN/KO/ZH spBLEU on FLORES (committed script), then build the AI Hub model dir (generative T5/decoder export — mirror the MT/LLM patterns; heavy like MADLAD). Run temp on a rootfs-backed directory (e.g. `TMPDIR=$HOME/bigtmp`), serially — never parallel heavy downloads (the tmpfs `/tmp` is only 31 GB and filling it crashes the shell).
2. **Kokoro / Piper-VN**: create a Python 3.11 conda env with each model's deps; run `…export` to validate; then push + PR.
3. **MADLAD-3B**: 6 GB download + 3B trace; validate compile via the same ONNX-source/serialize path if torch-trace is too heavy.

## Operating notes (lessons learned)
- One model at a time; `TMPDIR` on rootfs (`/`, 192 GB), never the 31 GB tmpfs `/tmp`.
- Every commit signed off: `git commit -s` (DCO is the gating check on external PRs).
- Validate on AI Hub (compile + profile + inference) **before** opening a PR.
- No personal attribution in source files (uniform Qualcomm header); credit is the git author + PR.
