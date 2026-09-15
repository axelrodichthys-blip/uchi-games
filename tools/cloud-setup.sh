#!/usr/bin/env bash
# クラウド環境（Claude Code on the web の Linux サンドボックス）に
# Godot 4（本体 + Web 書き出しテンプレート）と Blender を導入する。
#
# 使い方:
#   bash tools/cloud-setup.sh              # Godot + Blender
#   bash tools/cloud-setup.sh --godot-only # Godot だけ（GitHub Actions などで使う）
#   GODOT_VERSION=4.7.2 bash tools/cloud-setup.sh
#
# 何度実行しても壊れない（導入済みならスキップする）。
set -euo pipefail

GODOT_VERSION="${GODOT_VERSION:-4.7.2}"
GODOT_TAG="${GODOT_VERSION}-stable"
GODOT_BASE_URL="https://github.com/godotengine/godot/releases/download/${GODOT_TAG}"
GODOT_EDITOR_ZIP="Godot_v${GODOT_TAG}_linux.x86_64.zip"
GODOT_TEMPLATES_TPZ="Godot_v${GODOT_TAG}_export_templates.tpz"

INSTALL_DIR="${GODOT_INSTALL_DIR:-$HOME/.local/godot}"
BIN_DIR="${GODOT_BIN_DIR:-/usr/local/bin}"
TEMPLATES_DIR="$HOME/.local/share/godot/export_templates/${GODOT_VERSION}.stable"
CACHE_DIR="${GODOT_CACHE_DIR:-$HOME/.cache/uchi-games}"

WITH_BLENDER=1
for arg in "$@"; do
  case "$arg" in
    --godot-only) WITH_BLENDER=0 ;;
    -h|--help) sed -n '2,12p' "$0"; exit 0 ;;
    *) echo "不明な引数: $arg" >&2; exit 1 ;;
  esac
done

log() { echo "[cloud-setup] $*"; }

download() {
  # download <url> <dest>  … 途中失敗に備えて最大4回リトライ
  local url="$1" dest="$2" i
  for i in 1 2 3 4; do
    if curl -fL --retry 3 --retry-delay 2 -o "$dest.part" "$url"; then
      mv "$dest.part" "$dest"
      return 0
    fi
    log "ダウンロード失敗 ($i/4): $url"
    sleep $((i * 2))
  done
  return 1
}

mkdir -p "$INSTALL_DIR" "$CACHE_DIR"

# ---------------------------------------------------------------- Godot 本体
GODOT_BIN="$INSTALL_DIR/Godot_v${GODOT_TAG}_linux.x86_64"
if [ -x "$GODOT_BIN" ]; then
  log "Godot ${GODOT_VERSION} は導入済み: $GODOT_BIN"
else
  log "Godot ${GODOT_VERSION} 本体をダウンロード中..."
  download "$GODOT_BASE_URL/$GODOT_EDITOR_ZIP" "$CACHE_DIR/$GODOT_EDITOR_ZIP"
  unzip -oq "$CACHE_DIR/$GODOT_EDITOR_ZIP" -d "$INSTALL_DIR"
  chmod +x "$GODOT_BIN"
  rm -f "$CACHE_DIR/$GODOT_EDITOR_ZIP"
fi
if [ -w "$BIN_DIR" ]; then
  ln -sf "$GODOT_BIN" "$BIN_DIR/godot"
else
  sudo ln -sf "$GODOT_BIN" "$BIN_DIR/godot"
fi

# ------------------------------------------------- Web 書き出しテンプレート
# .tpz は全プラットフォーム入り（約1GB）なので、必要な web_* だけ展開する。
if ls "$TEMPLATES_DIR"/web_nothreads_release.zip >/dev/null 2>&1; then
  log "Web 書き出しテンプレートは導入済み: $TEMPLATES_DIR"
else
  log "書き出しテンプレート (${GODOT_TEMPLATES_TPZ}) をダウンロード中（約1GB、数分かかる）..."
  download "$GODOT_BASE_URL/$GODOT_TEMPLATES_TPZ" "$CACHE_DIR/$GODOT_TEMPLATES_TPZ"
  mkdir -p "$TEMPLATES_DIR"
  # tpz は zip。中身は templates/<name> なので web 関連と version.txt だけ取り出す
  unzip -oq "$CACHE_DIR/$GODOT_TEMPLATES_TPZ" 'templates/web_*' 'templates/version.txt' -d "$CACHE_DIR/tpz"
  mv "$CACHE_DIR/tpz/templates/"* "$TEMPLATES_DIR/"
  rm -rf "$CACHE_DIR/tpz" "$CACHE_DIR/$GODOT_TEMPLATES_TPZ"
fi

# --------------------------------------------------------------- Blender
if [ "$WITH_BLENDER" = "1" ]; then
  if command -v blender >/dev/null 2>&1; then
    log "Blender は導入済み: $(command -v blender)"
  else
    log "Blender を apt で導入中..."
    export DEBIAN_FRONTEND=noninteractive
    SUDO=""; [ "$(id -u)" != "0" ] && SUDO="sudo"
    # 一部 PPA が壊れていても止まらないように update の失敗は無視する
    $SUDO apt-get update -qq 2>/dev/null || true
    $SUDO apt-get install -y -qq --no-install-recommends blender >/dev/null
  fi
fi

# ----------------------------------------------------------------- 確認
log "確認:"
godot --headless --version
ls "$TEMPLATES_DIR"
if [ "$WITH_BLENDER" = "1" ]; then
  blender --background --version | head -1
fi
log "完了"
