#!/usr/bin/env bash
# .glb を四面（正面 / 左 / 背面 / 右）から描いて PNG に並べる。ターンアラウンドの見比べ用。
#   bash tools/model-view.sh build/traveler res://assets/traveler_preview.glb 1.6
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$1"; MODEL="$2"; HEIGHT="${3:-1.6}"
RES="${RES:-420x640}"
mkdir -p "$(dirname "$OUT")"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
xvfb-run -a -s "-screen 0 ${RES}x24" \
  godot --path game --rendering-driver opengl3 --audio-driver Dummy --resolution "$RES" \
    res://tools/model_view.tscn -- "$(realpath -m "$OUT")" "$MODEL" "$HEIGHT" 2>&1 | grep "^\[model_view\]" || true
