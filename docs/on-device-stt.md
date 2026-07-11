# On-Device Whisper STT

KO/ZH/EN speech recognition runs a real on-device Whisper engine — no cloud — replacing the
platform recogniser that was weak on Korean. Vietnamese keeps the PhoWhisper / platform path.

- **Engine:** sherpa-onnx (Apache-2.0, ONNX Runtime) — `package:sherpa_onnx`.
- **Model:** multilingual **Whisper-small int8**, pre-exported by the Next-gen Kaldi team
  (`csukuangfj/sherpa-onnx-whisper-small`, Whisper weights are MIT/OpenAI).
- **Capture:** `package:record` records a 16 kHz mono WAV; `sherpa.readWave` reads it directly.
- **Code:** `lib/whisper_stt.dart` (engine) + the `_listenWhisper` / `_onLevelWhisper` /
  `_endTurnWhisper` path in `lib/controller.dart`.
- **Threading:** the sherpa recognizer runs in a **dedicated worker isolate** — `WhisperStt`
  spawns it on the first decode and keeps it warm. The root isolate only resolves the model file
  paths (path_provider needs the platform method channel, unavailable in a background isolate) and
  awaits the result, so decode never blocks the UI. A synchronous in-process fallback runs if the
  isolate can't spawn, so on-device STT never regresses to unavailable.

## Lifecycle

```
Settings ▸ On-device speech ▸ Download  ──▶  ~375 MB downloaded once (HF), cached app-private
                                              (encoder 112 MB + decoder 262 MB + tokens)
tap mic (KO/ZH/EN side)  ──▶  record 16 kHz mono WAV
                          ──▶  energy-VAD endpoint (mic-sensitivity gate) or 30 s safety cap
                          ──▶  worker isolate: sherpa OfflineRecognizer.decode(WAV, lang=<ko|zh|en>)
                          ──▶  transcript ▶ MT ▶ TTS
```

Routing: `_useWhisper(side)` is true when on-device STT is enabled **and** the model is
downloaded **and** the side's language is KO/ZH/EN. Otherwise the controller uses the platform
`speech_to_text` recogniser (always the path for Vietnamese).

## Download

The model downloads on demand from Settings → On-device speech (not bundled in the APK, which
keeps the install small). Files are fetched to a `.part` file and renamed on success, so an
interrupted download is never mistaken for a complete one. `WhisperStt.isDownloaded()` gates
routing; `refreshWhisper()` re-checks after download or at startup.

## Verification (S25 Ultra, Snapdragon 8 Elite)

End-to-end on-device decode was verified on a FLEURS Korean clip — output identical to the
host sherpa-onnx 1.13.2 reference. Decode ≈ **0.38× real-time factor** (4.7 s for a 12.5 s clip,
debug build, CPU 2-thread), i.e. faster than real time; a typical ~4 s conversational turn
decodes in ~1.5 s.

## Known limitations / follow-ups

- **UI-thread blocking — resolved.** Decode now runs in a dedicated worker isolate (see
  *Threading* above), so a multi-second clip no longer blocks the root isolate / UI. A 30 s
  max-duration cap still bounds the worst case.
- **Language switch reloads the recognizer.** The Whisper `language` token is set at recognizer
  construction, so alternating KO↔ZH on the same side rebuilds it (a few hundred ms). Normal
  use (one language per side) hits the cached fast path.
- **Release build + GPU/NPU provider** would cut decode latency further (current numbers are a
  debug CPU build).
- **Mic→WAV link** is exercised by the live path; the model+config decode is proven against
  both host and on-device FLEURS WAVs.

## Reproduce the model-quality check (host)

```bash
pip install sherpa-onnx==1.13.2
# sherpa_onnx.OfflineRecognizer.from_whisper(encoder, decoder, tokens, language="ko")
# decode a FLEURS ko_kr clip; compare to the on-device transcript.
```
WER/CER for Whisper variants: `benchmarks/asr/bench_wer.py` (FLEURS, CC-BY-4.0).
On-device decode **latency** (warmup + best-of-N, worker-isolate IPC + decode): long-press the
Settings on-device-speech tile to run it, then aggregate with `benchmarks/latency/summarize.py`.
Latency numbers are device-only — run on the target before quoting them.
