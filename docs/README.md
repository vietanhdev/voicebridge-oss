# VoiceBridge — Documentation

Developer + reviewer documentation for VoiceBridge, the offline on-device VN ↔ EN/KO/ZH
speech + camera translator. Start with the repo [`README.md`](../README.md) for the overview.

## Contents

| Doc | What it covers |
|-----|----------------|
| [architecture.md](architecture.md) | Timing tiers, hot-path data flow, per-language routing, where code lives, privacy |
| [models.md](models.md) | Every pipeline model with measured numbers, licenses, sources, and how to swap/add one |
| [on-device-stt.md](on-device-stt.md) | On-device Whisper (sherpa-onnx): lifecycle, download, on-device verification, limitations |
| [aihub-contributions-plan.md](aihub-contributions-plan.md) | Qualcomm AI Hub contribution plan + status (submitted PRs, Gemma 4 E2B/E4B, deferred models) |
| [benchmark-2026-05-25.md](benchmark-2026-05-25.md) | Dated on-device measurement snapshot (historical) |

## Benchmarks & selection rationale

The measurement scripts, result JSON, and selection reports live under
[`../benchmarks/`](../benchmarks):

- `benchmarks/npu-benchmark.md` — Qualcomm AI Hub NPU latency report (S25 Ultra).
- `benchmarks/asr/`, `benchmarks/mt/`, `benchmarks/ocr/`, `benchmarks/tts/` — runnable benches.

All user-facing numbers come from committed bench scripts on public datasets; see the
selection policy at the top of [models.md](models.md).
