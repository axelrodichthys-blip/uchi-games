#!/usr/bin/env python3
# ターンアラウンド画像（4 面が横に並んだ 1 枚）を、1 面ずつの正方形 PNG に切り出す。
#
#   python3 tools/split_turnaround.py docs/reference/character/traveler_turnaround_poncho.png \
#           docs/reference/character/ai_input poncho
#
# 画像から 3D を作る AI サービス（Tripo / Meshy など）は「1 枚に 1 体」を前提にしているので、
# 4 面図をそのまま渡すと 4 体並んだ物や平べったい板が出てくる。1 面ずつに割って渡す。
# 出力は白背景・正方形・被写体を中央に置いたもの（サービスが好む形）。
import os
import sys

from PIL import Image

BG = 720          # R+G+B がこれより大きければ背景（白）
MARGIN = 0.12     # 正方形にしたときの余白（辺の長さに対する割合）

def views(px, W, H):
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
    return runs

def main(src, out_dir, prefix):
    im = Image.open(src).convert("RGB")
    W, H = im.size
    px = im.load()
    os.makedirs(out_dir, exist_ok=True)
    runs = views(px, W, H)
    # 面の順: 正面 → 左側面 → 背面 → 右側面
    # （画面の左を向いている面が「キャラの左側面」。ブーツのつま先の向きで見分けられる）
    names = ["1_front", "2_left", "3_back", "4_right"]
    print("%s: %d 面を検出" % (src, len(runs)))
    for i, (x0, x1) in enumerate(runs):
        ys = [y for y in range(H) if any(sum(px[x, y]) < BG for x in range(x0, x1))]
        top, bot = ys[0], ys[-1]
        crop = im.crop((x0, top, x1, bot + 1))
        # 正方形の白いカンバスの中央に置く
        side = int(max(crop.width, crop.height) * (1.0 + MARGIN * 2))
        canvas = Image.new("RGB", (side, side), (255, 255, 255))
        canvas.paste(crop, ((side - crop.width) // 2, (side - crop.height) // 2))
        name = names[i] if i < len(names) else "%d_view" % (i + 1)
        path = os.path.join(out_dir, "%s_%s.png" % (prefix, name))
        canvas.save(path)
        print("  %s  (%dx%d)" % (path, side, side))

if __name__ == "__main__":
    if len(sys.argv) < 4:
        print("使い方: python3 tools/split_turnaround.py <ターンアラウンド.png> <出力フォルダ> <頭に付ける名前>")
        sys.exit(1)
    main(sys.argv[1], sys.argv[2], sys.argv[3])
