#!/usr/bin/env bash
# Web 書き出し（build/web）を headless Chromium で起動し、コンソールのエラーとスクリーンショットを確認する。
#   bash tools/web-check.sh [出力.png] [待ち秒]
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="${1:-build/web_shot.png}"
WAIT="${2:-25}"
PORT=8765
CHROME="$(ls -d /opt/pw-browsers/chromium-*/chrome-linux/chrome 2>/dev/null | head -1)"
[ -z "$CHROME" ] && CHROME="$(command -v chromium || command -v chromium-browser || command -v google-chrome)"
mkdir -p "$(dirname "$OUT")"
python3 -m http.server "$PORT" --directory build/web >/dev/null 2>&1 &
SERVER=$!
trap 'kill $SERVER 2>/dev/null || true' EXIT
sleep 1
LOG="$(mktemp)"
timeout $((WAIT + 30)) "$CHROME" --headless=new --no-sandbox --disable-gpu --use-angle=swiftshader --enable-unsafe-swiftshader \
  --enable-logging=stderr --v=0 --window-size=1280,720 --virtual-time-budget=$((WAIT * 1000)) \
  --screenshot="$(realpath -m "$OUT")" "http://127.0.0.1:$PORT/" 2>"$LOG" || true
echo "[web-check] コンソール（error / warn / Godot の出力）:"
grep -iE "CONSOLE|error|uncaught" "$LOG" | grep -v "fontdata\|GPU stall\|Vulkan\|dbus\|sandbox\|OpenGL ES" | head -30 || true
echo "[web-check] スクリーンショット: $OUT"
rm -f "$LOG"
