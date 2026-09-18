# AI 3D 生成サービス（Tripo / Meshy など）から落としたメッシュを、このプロジェクトの寸法に揃える。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/normalize_sculpt.py -- <入力> <出力.glb> [身長m] [向きの角度]
#   例: blender --background --python tools/blender/normalize_sculpt.py -- \
#         docs/reference/character/ai_sculpt/poncho_raw.glb game/assets/sculpt_ref.glb 1.6 0
#
# 入力は .glb / .gltf / .obj / .fbx。やること:
#   1. メッシュを 1 つにまとめる
#   2. 一番長い軸を「上」とみなして立たせる（横倒しで出てくることがある）
#   3. 第 4 引数の角度だけ上下軸まわりに回す（正面が -Z を向くように直す。既定 0 度）
#   4. 身長を第 3 引数に合わせ、靴底を 0、左右と前後の中心を原点に置く
#   5. .glb に書き出す（そのあと tools/model-view.sh で四面図にできる）
#
# これは **見比べるための参考** を作るスクリプト。ゲームに入れるモデルではない。
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    print("使い方: blender --background --python normalize_sculpt.py -- <入力> <出力.glb> [身長m] [向きの角度]")
    sys.exit(1)
src, out_path = argv[0], argv[1]
target_h = float(argv[2]) if len(argv) >= 3 else 1.6
yaw_deg = float(argv[3]) if len(argv) >= 4 else 0.0

bpy.ops.wm.read_factory_settings(use_empty=True)

ext = os.path.splitext(src)[1].lower()
if ext in (".glb", ".gltf"):
    bpy.ops.import_scene.gltf(filepath=src)
elif ext == ".obj":
    bpy.ops.wm.obj_import(filepath=src, forward_axis="NEGATIVE_Z", up_axis="Y")
elif ext == ".fbx":
    bpy.ops.import_scene.fbx(filepath=src)
else:
    print("[sculpt] 読めない形式です: %s（.glb / .gltf / .obj / .fbx）" % ext)
    sys.exit(1)

meshes = [o for o in bpy.data.objects if o.type == "MESH"]
if not meshes:
    print("[sculpt] メッシュが見つかりません")
    sys.exit(1)
bpy.ops.object.select_all(action="DESELECT")
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
if len(meshes) > 1:
    bpy.ops.object.join()
obj = bpy.context.active_object
obj.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)

def bbox():
    cos = [obj.matrix_world @ v.co for v in obj.data.vertices]
    lo = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
    hi = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
    return lo, hi

lo, hi = bbox()
size = hi - lo
print("[sculpt] 読み込み: 頂点 %d / 面 %d / 大きさ X%.3f Y%.3f Z%.3f"
      % (len(obj.data.vertices), len(obj.data.polygons), size.x, size.y, size.z))

# 一番長い軸を「上」にする（Blender は Z が上）
longest = max(range(3), key=lambda i: (size.x, size.y, size.z)[i])
if longest != 2:
    import math
    if longest == 0:
        obj.rotation_euler = (0.0, math.radians(90.0), 0.0)
    else:
        obj.rotation_euler = (math.radians(-90.0), 0.0, 0.0)
    bpy.ops.object.transform_apply(rotation=True)
    print("[sculpt] 横倒しだったので立てた（長い軸 %s → Z）" % "XYZ"[longest])

if abs(yaw_deg) > 1e-6:
    import math
    obj.rotation_euler = (0.0, 0.0, math.radians(yaw_deg))
    bpy.ops.object.transform_apply(rotation=True)
    print("[sculpt] 上下軸まわりに %.1f 度回した" % yaw_deg)

lo, hi = bbox()
h = hi.z - lo.z
if h <= 0:
    print("[sculpt] 高さが 0 です")
    sys.exit(1)
factor = target_h / h
obj.scale = Vector((factor, factor, factor))
bpy.ops.object.transform_apply(scale=True)
lo, hi = bbox()
obj.location = Vector((-(lo.x + hi.x) * 0.5, -(lo.y + hi.y) * 0.5, -lo.z))
bpy.ops.object.transform_apply(location=True)
lo, hi = bbox()
print("[sculpt] 身長 %.3f m に正規化（%.3f 倍）/ 幅 %.3f / 奥行き %.3f / 靴底 %.4f"
      % (hi.z - lo.z, factor, hi.x - lo.x, hi.y - lo.y, lo.z))

os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB", export_yup=True)
print("[sculpt] 書き出し: %s" % out_path)
print("[sculpt] 次: bash tools/model-view.sh build/sculpt %s %.2f"
      % (out_path.replace("game/assets/", "res://assets/"), target_h))
