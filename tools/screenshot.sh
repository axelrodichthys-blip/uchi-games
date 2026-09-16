#!/usr/bin/env bash
# GPU の無いクラウド環境で、ソフトウェアレンダリング（xvfb + Mesa）を使って
# ゲーム画面のスクリーンショットを撮る。
#   bash tools/screenshot.sh [出力.png] [描画フレーム数] [walk|run|jump|hop|idle|walk_away|run_away] [枚数] [間隔フレーム] [ワールド.tscn]
#   例: WORLD=res://scenes/worlds/gray/gray_world.tscn bash tools/screenshot.sh build/g.png 60 walk
#   縦画面（スマホの確認）: RES=480x960 bash tools/screenshot.sh build/phone.png 60
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/screenshot.png}"
FRAMES="${2:-30}"
mkdir -p "$(dirname "$OUT")"
export LIBGL_ALWAYS_SOFTWARE=1
export GALLIUM_DRIVER="${GALLIUM_DRIVER:-llvmpipe}"
SCREEN="${RES:-1280x720}"
xvfb-run -a -s "-screen 0 ${SCREEN}x24" \
  godot --path game --rendering-driver opengl3 --audio-driver Dummy --resolution "$SCREEN" \
    res://tools/screenshot_runner.tscn -- "$(realpath -m "$OUT")" "$FRAMES" "${3:-}" "${4:-1}" "${5:-6}" "${6:-${WORLD:-}}"
echo "[screenshot] $OUT"
