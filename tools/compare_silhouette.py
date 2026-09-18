#!/usr/bin/env python3
# 「基準画像の正面」と「モデルを描いた正面」のシルエットの幅を、高さごとに並べて比べる。
#
#   python3 tools/compare_silhouette.py \
#       docs/reference/character/traveler_turnaround_poncho.png build/full_1.png
#
# どちらの画像も「背景が明るい単色」であればよい（基準画像は白、model-view.sh の出力は薄い灰色）。
# 幅は「身長に対する割合」で出すので、画像の大きさが違っても比べられる。
# 差が大きい高さに <<< が付く。最後に平均と最大のずれを cm（身長 160cm 換算）で出す。
import sys

from PIL import Image

def profile(path, bg):
    im = Image.open(path).convert("RGB")
    W, H = im.size
    px = im.load()
    cols = [any(sum(px[x, y]) < bg for y in range(0, H, 2)) for x in range(W)]
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
    if not runs:
        raise SystemExit("被写体が見つかりません: %s（背景のしきい値 %d を見直す）" % (path, bg))
    x0, x1 = runs[0]                      # 左端の図（正面）だけを見る
    ys = [y for y in range(H) if any(sum(px[x, y]) < bg for x in range(x0, x1))]
    top, bot = ys[0], ys[-1]
    h = bot - top
    out = []
    for i in range(101):
        y = min(max(int(bot - i / 100.0 * h), top), bot)
        r = [x for x in range(x0, x1) if sum(px[x, y]) < bg]
        out.append((max(r) - min(r) + 1) / h if r else 0.0)
    return out

def main(ref_path, model_path, ref_bg=720, model_bg=690, height_cm=160.0):
    ref = profile(ref_path, ref_bg)
    mdl = profile(model_path, model_bg)
    print("高さ   基準    モデル    差")
    for i in range(0, 101, 4):
        d = mdl[i] - ref[i]
        print("%4.2f  %5.3f  %5.3f  %+6.3f%s"
              % (i / 100.0, ref[i], mdl[i], d, "  <<<" if abs(d) > 0.030 else ""))
    ds = [abs(mdl[i] - ref[i]) for i in range(2, 99)]
    print("平均のずれ %.1f cm / 最大 %.1f cm（身長 %.0fcm に対する幅の差）"
          % (sum(ds) / len(ds) * height_cm, max(ds) * height_cm, height_cm))

if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("使い方: python3 tools/compare_silhouette.py <基準画像> <モデルの正面 PNG> [基準の背景しきい値] [モデルの背景しきい値]")
        sys.exit(1)
    a = sys.argv[1:]
    main(a[0], a[1], int(a[2]) if len(a) > 2 else 720, int(a[3]) if len(a) > 3 else 690)
