#!/usr/bin/env python3
# 連番 PNG（base_1.png, base_2.png ...）を 1 枚に並べる。
#   python3 tools/sheet.py build/shot build/sheet.png [left,top,right,bottom の切り抜き]
import sys, glob
from PIL import Image
base, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(base + "_*.png"), key=lambda p: int(p.rsplit("_",1)[1].split(".")[0]))
crop = tuple(int(x) for x in sys.argv[3].split(",")) if len(sys.argv) > 3 else None
ims = [Image.open(f) for f in files]
if crop: ims = [im.crop(crop) for im in ims]
w, h = ims[0].size
cols = min(4, len(ims)); rows = (len(ims)+cols-1)//cols
sheet = Image.new("RGB", (w*cols, h*rows), "white")
for i, im in enumerate(ims): sheet.paste(im, ((i%cols)*w, (i//cols)*h))
sheet.save(out); print(out, sheet.size)
