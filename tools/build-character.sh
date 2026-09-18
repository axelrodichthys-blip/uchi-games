#!/usr/bin/env bash
# 本キャラを作ってゲームに入るところまで一気に通す。
#   bash tools/build-character.sh
#
# 流れ:
#   1. メッシュを組み立てる（見た目用 = 腕 18 度 / リグ用 = 腕 40 度）
#   2. 既存の Mixamo リグ（骨 + アニメ 10 本）をリグ用の素体に合わせ直す
#   3. ポンチョと帽子を被せる
#   4. マントを揺らす骨を差し込む → game/assets/traveler_cloth.glb（ゲームが読むもの）
#
# Mixamo から本キャラのリグが届いたら、先に .glb へ変換してから RIG_SRC で渡す:
#   blender --background --python tools/blender/mixamo_fbx_to_glb.py -- \
#     docs/reference/mixamo_body build/traveler_mixamo_new.glb \
#     "$(cat docs/reference/character/traveler_rig_proxy_height.txt)" \
#     docs/reference/character/traveler_body_rig_proxy.obj
#   RIG_SRC=build/traveler_mixamo_new.glb bash tools/build-character.sh
#
# 環境変数:
#   RIG_SRC    … 骨とアニメのもとになる .glb（既定は今の流用リグ game/assets/traveler_mixamo.glb）
#   RIG_PROXY=1 … リグ用の簡単な身体（traveler_body_rig_proxy.obj）も作る
set -euo pipefail
cd "$(dirname "$0")/.."
B="${BLENDER:-blender}"
RIG_SRC="${RIG_SRC:-game/assets/traveler_mixamo.glb}"

echo "[1/4] メッシュを組み立てる（見た目用: 腕 18 度）"
"$B" --background --python tools/blender/build_traveler.py 2>&1 | grep -E "^\[traveler\]" || true

echo "[2/4] リグ用の素体（腕 40 度。既存リグの休めの姿勢に合わせる）"
UCHI_ARM_ANGLE=40 UCHI_SUFFIX=_rig "$B" --background --python tools/blender/build_traveler.py 2>&1 | grep -E "^\[traveler\] 腕の開き" || true

if [ "${RIG_PROXY:-}" = "1" ]; then
  echo "[2b] Mixamo の自動リグ用の簡単な身体（指なし・ひとつながり）"
  UCHI_ARM_ANGLE=40 UCHI_SUFFIX=_rig_proxy UCHI_RIG_PROXY=1 \
    "$B" --background --python tools/blender/build_traveler.py 2>&1 | grep -E "^\[traveler\] (ボクセル|Mixamo|腕の開き)" || true
fi

echo "[3/4] リグ（$RIG_SRC）を合わせ直して被せる"
"$B" --background --python tools/blender/retarget_rig.py -- \
  "$RIG_SRC" game/assets/traveler_body_rig.glb build/traveler_rigged.glb \
  2>&1 | grep -E "^\[retarget\]" || true
"$B" --background --python tools/blender/add_outfit.py -- \
  build/traveler_rigged.glb game/assets/traveler_outfit.glb build/traveler_dressed.glb \
  2>&1 | grep -E "^\[outfit\]" || true

echo "[4/4] マントの揺れの骨"
"$B" --background --python tools/blender/add_cloth_bones.py -- \
  build/traveler_dressed.glb game/assets/traveler_cloth.glb \
  2>&1 | grep -E "^\[cloth\]" || true

echo "---- できあがり: game/assets/traveler_cloth.glb（ゲームが読むキャラ）"
echo "     確認: godot --headless --path game --import"
echo "           godot --headless --path game res://tools/walk_test.tscn"
echo "           godot --headless --path game res://tools/foot_probe.tscn   # 接地判定の値"
echo "           CLIP=Walking CLIP_T=0.35 bash tools/model-view.sh build/wk res://assets/traveler_cloth.glb 1.6"
