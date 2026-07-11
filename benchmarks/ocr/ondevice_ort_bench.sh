#!/usr/bin/env bash
# On-device PP-OCRv5 ONNX latency bench on the S25 Ultra (on-device
# latency is 50% of Technical Excellence). Large model assets are pulled from
# HuggingFace (monkt/paddleocr-onnx, Apache-2.0) — NOT committed to this repo.
#
# Pipeline: fetch ONNX models -> adb push to the app external dir -> you trigger
# controller.ortBenchmark() by long-pressing the Lens "live" dot -> pull JSON.
#
# Prereqs: adb connected to the phone (wireless: re-toggle Settings > Developer
# options > Wireless debugging, then `adb pair` + `adb connect`), app installed.
#
# Usage: ./ondevice_ort_bench.sh [adb-serial]   e.g. ./ondevice_ort_bench.sh 192.168.1.104:46465
set -euo pipefail
SERIAL="${1:-}"
ADB=(adb); [ -n "$SERIAL" ] && ADB=(adb -s "$SERIAL")
PKG=com.nrl.voicebridge
EXT="/sdcard/Android/data/$PKG/files/ocr_bench/models"
CACHE="${TMPDIR:-/tmp}/ppv5"
HF="https://huggingface.co/monkt/paddleocr-onnx/resolve/main"

mkdir -p "$CACHE"
fetch() { # url dest
  [ -s "$CACHE/$2" ] || { echo "fetch $2"; curl -fsSL "$HF/$1" -o "$CACHE/$2"; }
}
fetch "detection/v3/det.onnx"        det_v3.onnx       # mobile det proxy (2.4 MB)
fetch "languages/korean/rec.onnx"    ko_rec.onnx       # mobile KO rec (13 MB)
fetch "languages/latin/rec.onnx"     latin_rec.onnx    # mobile Latin rec (7.6 MB)
fetch "languages/chinese/rec.onnx"   zh_rec.onnx       # NB: server ZH rec (81 MB)

"${ADB[@]}" shell mkdir -p "$EXT"
for m in det_v3 ko_rec latin_rec zh_rec; do
  echo "push $m.onnx"; "${ADB[@]}" push "$CACHE/$m.onnx" "$EXT/$m.onnx" >/dev/null
done
echo
echo "Models pushed. Now on the phone: open Lens, LONG-PRESS the amber 'live' dot"
echo "(top-left of the camera). Watch: adb logcat | grep VB-ORT"
echo "Then pull results:"
echo "  ${ADB[*]} shell run-as $PKG cat /data/data/$PKG/app_flutter/ort_bench.json > results_ort_ondevice.json"
echo "  python3 -c \"import json;[print(r) for r in json.load(open('results_ort_ondevice.json'))]\""
