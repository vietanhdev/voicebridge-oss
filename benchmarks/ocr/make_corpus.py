#!/usr/bin/env python3
"""Generate a synthetic ground-truth OCR corpus of industrial-safety signs.

VoiceBridge targets factory-floor sign translation, so
the corpus is single-register *printed* safety signage in ZH (Simplified), KO,
and VI. Each image is one sign with known text; ground truth is written to
``groundtruth.json`` for CER scoring.

HONESTY NOTE: this is a SYNTHETIC, clean, printed-text
set — high contrast, no perspective/blur/glare. It measures recognizer quality
on legible signage, NOT real-world robustness. Register: industrial safety,
one short phrase per image. Size is small (see counts below). Do not generalize
these numbers to handwriting, low light, or curved/edge text.

Run:  python3 make_corpus.py   ->   writes corpus/*.png + groundtruth.json
Deterministic: no randomness, so a clean clone reproduces byte-identical images.

Author: Viet-Anh Nguyen (vietanh@nrl.ai), Neural Research Lab.
"""
import json
import os
from PIL import Image, ImageDraw, ImageFont

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "corpus")

CJK = "/usr/share/fonts/opentype/noto/NotoSansCJK-Bold.ttc"
LATIN = "/usr/share/fonts/truetype/noto/NotoSans-Bold.ttf"
# Noto Sans CJK-Bold.ttc subfont order (verified via fontTools): 1=KR, 2=SC.
TTC_IDX = {"ko": 1, "zh": 2}

# (text, [lines]) — industrial-safety register. Translations are paired across
# languages where natural, so ZH/KO/VI cover the same hazard concepts.
SIGNS = {
    "zh": [
        ["紧急停止"], ["佩戴安全帽"], ["禁止入内"], ["高压电危险"],
        ["当心触电"], ["必须戴防护眼镜"], ["小心地滑"], ["禁止吸烟"],
        ["注意安全", "戴好手套"], ["消防通道", "禁止堵塞"],
    ],
    "ko": [
        ["비상 정지"], ["안전모 착용"], ["출입 금지"], ["고압 전기 위험"],
        ["감전 주의"], ["보안경 착용"], ["미끄럼 주의"], ["금연"],
        ["안전 제일", "장갑 착용"], ["소방 통로", "적재 금지"],
    ],
    "vi": [
        ["DỪNG KHẨN CẤP"], ["ĐỘI MŨ BẢO HỘ"], ["CẤM VÀO"], ["NGUY HIỂM ĐIỆN CAO ÁP"],
        ["CẨN THẬN ĐIỆN GIẬT"], ["ĐEO KÍNH BẢO HỘ"], ["CẨN THẬN TRƠN TRƯỢT"], ["CẤM HÚT THUỐC"],
        ["AN TOÀN LÀ TRÊN HẾT", "ĐEO GĂNG TAY"], ["LỐI THOÁT HIỂM", "KHÔNG CHẮN LỐI"],
    ],
}

W, H = 900, 360
PAD = 40


def font_for(lang, size):
    if lang in TTC_IDX:
        return ImageFont.truetype(CJK, size, index=TTC_IDX[lang])
    return ImageFont.truetype(LATIN, size)


def render(lang, lines, path):
    img = Image.new("RGB", (W, H), "white")
    d = ImageDraw.Draw(img)
    # shrink font until the widest line fits the padded box
    size = 110
    while size > 24:
        f = font_for(lang, size)
        widest = max(d.textbbox((0, 0), ln, font=f)[2] for ln in lines)
        line_h = d.textbbox((0, 0), "Ag", font=f)[3]
        total_h = line_h * len(lines) + (len(lines) - 1) * 16
        if widest <= W - 2 * PAD and total_h <= H - 2 * PAD:
            break
        size -= 4
    f = font_for(lang, size)
    line_h = d.textbbox((0, 0), "Ag", font=f)[3]
    total_h = line_h * len(lines) + (len(lines) - 1) * 16
    y = (H - total_h) // 2
    for ln in lines:
        w = d.textbbox((0, 0), ln, font=f)[2]
        d.text(((W - w) // 2, y), ln, font=f, fill=(12, 12, 12))
        y += line_h + 16
    img.save(path)


def main():
    os.makedirs(OUT, exist_ok=True)
    gt = []
    for lang, signs in SIGNS.items():
        for i, lines in enumerate(signs):
            fid = f"{lang}_{i:02d}"
            fn = f"{fid}.png"
            render(lang, lines, os.path.join(OUT, fn))
            gt.append({
                "id": fid,
                "lang": lang,
                "lines": lines,
                "text": " ".join(lines),
                "file": fn,
            })
    with open(os.path.join(HERE, "groundtruth.json"), "w", encoding="utf-8") as fp:
        json.dump(gt, fp, ensure_ascii=False, indent=2)
    n = len(gt)
    per = {l: sum(1 for g in gt if g["lang"] == l) for l in SIGNS}
    print(f"wrote {n} signs -> {OUT}  ({per})")


if __name__ == "__main__":
    main()
