#!/usr/bin/env bash
# アニメクリップを指定時刻で描画して PNG を並べる（ジャンプ・着地の切れ目探し用）。
#   bash tools/clip-view.sh build/jumpclip Jump 0.0,0.2,0.4,0.6
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; CLIP="$2"; TIMES="$3"
mkdir -p "$(dirname "$OUT")"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
xvfb-run -a -s "-screen 0 480x480x24" \
  godot --path game --rendering-driver opengl3 --audio-driver Dummy --resolution 480x480 \
    res://tools/clip_view.tscn -- "$(realpath -m "$OUT")" "$CLIP" "$TIMES" 2>&1 | grep "^\[clip_view\]" || true
