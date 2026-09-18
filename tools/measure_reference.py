#!/usr/bin/env python3
# 確定ターンアラウンドの画像を画素で測って、モデルの寸法表のもとを出す。
#   python3 tools/measure_reference.py docs/reference/character/traveler_turnaround_poncho.png
# 出すもの:
#   1. 正面の図の「高さ 0（靴底）〜 1（てっぺん）」に対する幅
#   2. 幅が大きく変わる高さ（ブーツの上端・ポンチョの裾・襟・つば などの境目）
#   3. 各高さで見えている色（パレットに最も近いもの）
# Pillow だけで動く（numpy は使わない）。
import sys
from PIL import Image

PALETTE = {
    "cloth": (0xBA, 0xA9, 0x90), "body": (0x3A, 0x39, 0x37), "eye": (0xF2, 0xED, 0xE3),
    "boot": (0x66, 0x5C, 0x51), "button": (0x87, 0x7A, 0x6A), "vest": (0xC4, 0xB0, 0x98),
    "glove": (0xDB, 0xCB, 0xB9), "shorts": (0x9C, 0x89, 0x70), "leather": (0x6C, 0x57, 0x47),
}
BG = 720          # R+G+B がこれより大きければ背景（白）とみなす
TOL = 900         # 色の距離（2乗）がこれ以内ならパレットのその色

def front_view(px, W, H):
    """左端の図（正面）の範囲を返す"""
    cols = [any(sum(px[x, y]) < BG for y in range(0, H, 2)) for x in range(W)]
    runs, start = [], None
    for x in range(W):
        if cols[x] and start is None:
            start = x
        if not cols[x] and start is not None:
            if x - start > 30:
                runs.append((start, x))
            start = None
    if start is not None:
        runs.append((start, W))
    x0, x1 = runs[0]
    ys = [y for y in range(H) if any(sum(px[x, y]) < BG for x in range(x0, x1))]
    return x0, x1, ys[0], ys[-1], len(runs)

def main(path):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    x0, x1, top, bot, n = front_view(px, W, H)
    h = bot - top
    print("%s: %d ビュー / 正面 x %d-%d, 高さ %d px" % (path, n, x0, x1, h))

    def width_at(y):
        xs = [x for x in range(x0, x1) if sum(px[x, y]) < BG]
        return (max(xs) - min(xs) + 1) if xs else 0

    print("-- 幅（高さ 0 = 靴底, 1 = てっぺん）")
    ws = []
    for i in range(101):
        y = min(max(int(bot - i / 100 * h), top), bot)
        ws.append((i / 100.0, width_at(y) / h))
    for f, w in ws[::5]:
        print("   %4.2f  %5.3f × 身長" % (f, w))
    print("-- 幅が大きく変わるところ（部位の境目）")
    for j in range(1, len(ws)):
        if abs(ws[j][1] - ws[j - 1][1]) > 0.035:
            print("   %4.2f (%5.3f) → %4.2f (%5.3f)" % (ws[j - 1][0], ws[j - 1][1], ws[j][0], ws[j][1]))

    print("-- その高さで 8 画素以上ある色")
    prev = None
    for y in range(top, bot + 1):
        cnt = {}
        for x in range(x0, x1):
            r, g, b = px[x, y]
            if r + g + b > BG:
                continue
            best, bd = None, 1 << 30
            for k, (pr, pg, pb) in PALETTE.items():
                d = (r - pr) ** 2 + (g - pg) ** 2 + (b - pb) ** 2
                if d < bd:
                    bd, best = d, k
            if bd < TOL:
                cnt[best] = cnt.get(best, 0) + 1
        key = tuple(sorted(k for k, v in cnt.items() if v >= 8))
        if key != prev:
            print("   %5.3f  %s" % ((bot - y) / h, ", ".join(key) if key else "-"))
            prev = key

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("使い方: python3 tools/measure_reference.py <画像.png>")
        sys.exit(1)
    main(sys.argv[1])
