# On-device Whisper STT latency benchmark

Measures the wall-clock latency a user actually experiences for the KO/ZH/EN
on-device STT leg: `WhisperStt.transcribeWav` end to end, which since the isolate
refactor runs in a **dedicated worker isolate** (so the number includes the real
isolate IPC + sherpa-onnx decode, not just the FFI call).

This is the on-device half of the latency budget. Quality
(WER/CER) is measured separately in [`../asr/`](../asr); this directory is
latency only.

## Protocol

- **Warmup:** 3 decodes per clip, discarded (cold-start / model-load excluded).
- **Timing:** best-of-5 per clip; we keep per-clip **best** and **median** ms.
- **Engine:** Whisper-small int8, sherpa-onnx, CPU provider, worker isolate.
- **Device:** report the exact unit (e.g. Samsung Galaxy S25 Ultra, SM-S938B) and
  `adb shell getprop ro.soc.model` next to any number. A latency figure without a
  device is not a result.
- **Numbers are produced on-device only.** Nothing in this repo is pre-filled —
  run the steps below to generate `whisper_latency.json`, then summarise it.

## Corpus

Real speech clips, not synthetic TTS. Use held-out utterances from a public set
(e.g. FLEURS test, CommonVoice) per language; 16 kHz mono WAV (the recorder
captures this format). State the source set + clip count when reporting.

`manifest.example.json` shows the schema (`[{id, lang, file}]`, lang in
`ko`/`zh`/`en`). Copy it to `manifest.json` and list your clips.

## Run

1. Download the Whisper model in-app (Settings → on-device speech).
2. Push the corpus to the app external files dir:

   ```sh
   adb push manifest.json /sdcard/Android/data/com.nrl.voicebridge/files/whisper_latency/manifest.json
   adb push ko-01.wav     /sdcard/Android/data/com.nrl.voicebridge/files/whisper_latency/ko-01.wav
   # … one push per clip
   ```

3. **Long-press the Settings on-device-speech tile** to run the benchmark
   (`[VB-LAT]` lines stream to logcat; progress shows in the status bar).
4. Pull the result and summarise:

   ```sh
   adb pull <app-documents>/whisper_latency.json .   # see logcat for the exact path
   python3 summarize.py whisper_latency.json
   ```

`summarize.py` prints a per-language + overall best/median table. Paste the
device string and corpus description alongside it — per the project benchmark policy, measure
first, then write the cited number.
