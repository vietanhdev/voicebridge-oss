# VoiceBridge on-device benchmark — 2026-05-25

**Device:** Samsung Galaxy S25 Ultra (SM-S938B), Qualcomm Snapdragon 8 Elite (SM8750), Android 16, 11.4 GB RAM.
**Build:** debug APK, Flutter 3.44 / Dart 3.12. MT engine: Google ML Kit on-device translation (`google_mlkit_translation` 0.13.1).
**Method:** 1 warmup call excluded, then **best-of-5 average** per pair, single sentence each. Wall-clock via `Stopwatch` around `translateText`. Measured 2026-05-25 via in-app self-test (long-press wordmark). Single device, single run-set — indicative, not a published claim.

## Machine translation latency (on-device, offline)

| Pair | Avg latency (ms/call) | Source sentence | Output | Functional |
|---|---|---|---|---|
| en→vi | 32.4 | Please wear your safety helmet before entering the line. | Vui lòng đeo mũ bảo hiểm an toàn của bạn trước khi vào dòng. | OK |
| vi→en | 25.2 | Cẩn thận, sàn nhà đang trơn trượt. | Be careful, the floor is slippery. | OK |
| en→ko | 20.4 | Where is the emergency exit? | 비상구는 어디에 있습니까? | OK |
| ko→vi | 35.4 | 비상구는 어디에 있습니까? | Trường hợp khẩn cấp ở đâu? | OK* |
| zh→vi | 37.0 | 请立即停止机器。 | Dừng máy ngay lập tức. | OK |
| vi→zh | 36.4 | Máy số ba đang gặp sự cố. | 第三号遇到了麻烦。 | OK* |

`*` ko→vi dropped "exit"; vi→zh dropped "machine" — terminology drift that the glossary / pronunciation layers are designed to correct.

**Takeaway:** the MT stage costs ~20–37 ms on-device — negligible vs ASR/TTS. The end-to-end latency budget is dominated by ASR and TTS, not MT (consistent with the cascade-vs-E2E literature reviewed for this pipeline).

## Other on-device verification (same session)

- **TTS voices present & speak:** vi-VN, en-US, ko-KR, zh-CN all `available=true`, all returned speak=1.
- **STT:** `initialize()=true`, 31 locales incl. ko & vi; captures audio (returns `error_no_match` only on silence).
- **Pronunciation dictionary:** "Check the ESD mat near the VinFast line." → "Check the E S D mat near the Vin Phát line." (applied to TTS input only).

## Not yet measured (for the paper — needs real experiments, no fabrication)

- ASR WER (VN/KO/ZH/EN) on a real corpus; ASR + TTS per-stage latency on-device.
- MT quality (BLEU/COMET) on a VN-centric test set with references.
- End-to-end spoken-turn latency (mic→audio-out) with a microphone harness.
- Comparison vs the edge-AI upgrade stack (Whisper-Turbo/PhoWhisper + MADLAD-400 + Supertonic-3).
