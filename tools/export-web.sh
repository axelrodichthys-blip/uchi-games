#!/usr/bin/env bash
# Web 書き出し。build/web/ に index.html ほかを出力する。
#   bash tools/export-web.sh            # release
#   bash tools/export-web.sh --debug    # debug
set -euo pipefail
cd "$(dirname "$0")/.."
MODE="--export-release"
[ "${1:-}" = "--debug" ] && MODE="--export-debug"
rm -rf build/web && mkdir -p build/web
# 取り直した直後は .godot/ が無いので、先にインポートしておく
godot --headless --path game --import >/dev/null 2>&1 || true
godot --headless --path game "$MODE" Web ../build/web/index.html
# GitHub Pages は Jekyll が _ 始まりのファイルを無視するので止める
touch build/web/.nojekyll
echo "[export-web] 出力:"
du -sh build/web
ls -la build/web
