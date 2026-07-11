# VI↔KO Machine Translation — diagnosis

User report: VI↔KO translation quality is poor. Investigated 2026-06-06.

## Hypothesis (WRONG — retracted)
"ML Kit pivots VI↔KO through English (VI→EN→KO), and the double-hop is the cause."

## Measured: English-pivot is NOT the culprit
Same model (NLLB-200-distilled-600M, FLORES-1012, spBLEU), direct vs English-pivot:

| direction | direct | EN-pivot | verdict |
|-----------|--------|----------|---------|
| VI→KO | 19.31 | **20.12** | pivot slightly *better* |
| KO→VI | 24.47 | 24.06 | ≈ equal |

Pivoting through English is ~equal to direct (English is the high-resource hub these
models train on). So the pivot is not why VI↔KO is bad. `bench_viko.py`.

## Real cause: model capacity
Absolute spBLEU is **low (~19–24) even for a 600M model**. ML Kit ships **tiny per-language
models (~30 MB)** — below NLLB-600M — so VI↔KO quality is capped by model size, not routing.

## Fix: ship a stronger MT model (already the project's pick)
- **Gemma 3n E2B** — 32.81 spBLEU on FLORES-1012 (measured) — ~13 spBLEU over NLLB-600M's
  VI→KO. Gemma 3n ships under Google's custom Gemma Terms (use-restricted, not Apache).
  Gemma 4 E2B is Apache-2.0 but has not yet been separately re-measured on this benchmark —
  don't assume the 32.81 number transfers. MADLAD-400-3B (32.01, Apache-2.0, license-clean)
  is the safer default until Gemma 4 is benchmarked. The app currently still ships ML Kit;
  wiring one of these as the MT engine is the actual improvement.
- Direct vs pivot routing is a non-issue — pick whatever the chosen model does best.

## Open: ML Kit on-device VI↔KO number
Measuring ML Kit's actual on-device spBLEU (via the app's FLORES bench) to complete the
current-vs-target comparison.

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
