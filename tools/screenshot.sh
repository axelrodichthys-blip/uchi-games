#!/usr/bin/env bash
# GPU の無いクラウド環境で、ソフトウェアレンダリング（xvfb + Mesa）を使って
# ゲーム画面のスクリーンショットを撮る。
#   bash tools/screenshot.sh [出力.png] [描画フレーム数] [walk|run|jump|idle] [枚数] [間隔フレーム]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/screenshot.png}"
FRAMES="${2:-30}"
mkdir -p "$(dirname "$OUT")"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
xvfb-run -a -s "-screen 0 1280x720x24" \
  godot --path game --rendering-driver opengl3 --audio-driver Dummy --resolution 1280x720 \
    res://tools/screenshot_runner.tscn -- "$(realpath -m "$OUT")" "$FRAMES" ${3:+"$3"} ${4:+"$4"} ${5:+"$5"}
echo "[screenshot] $OUT"
