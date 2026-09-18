# Mixamo でリグを付けた素体の .glb に、ポンチョと帽子（traveler_outfit.glb）を被せる。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/add_outfit.py -- <リグ済み.glb> <ポンチョ帽子.glb> <出力.glb>
#   例: blender --background --python tools/blender/add_outfit.py -- \
#         game/assets/traveler_rigged.glb game/assets/traveler_outfit.glb game/assets/traveler_dressed.glb
#
# やること:
#   1. リグ済みの .glb（アーマチュア + 素体メッシュ + アニメ）と、ポンチョ・帽子のメッシュを読む
#   2. ポンチョ・帽子の頂点に骨の重みを付ける
#      - つばより上（帽子）… Head に 1.0
#      - それ以外（ポンチョ）… 高さに応じて Hips / Spine / Spine1 / Spine2 / Neck を混ぜる
#        （骨の高さはアーマチュアから読むので、Mixamo が返す大きさが変わっても付いていく）
#   3. 素体メッシュと結合して 1 つのスキンメッシュにし、.glb に書き出す
#
# このあと add_cloth_bones.py を流すと、材質名が Cloth で始まる布（＝ポンチョ）に
# 揺れ用の骨の鎖が入る。帽子は Head に付いているので鎖の対象から自然に外れる。
import os
import sys

import bpy
from mathutils import Vector

# ポンチョと帽子の境目（素体の高さ m。build_traveler.py の BRIM と揃える）
HAT_SPLIT = 1.196
# 素体の設計上の高さ。build_traveler.py が書く traveler_body_height.txt を読む（無ければこの値）
HEIGHT_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)),
                           "..", "..", "docs", "reference", "character", "traveler_body_height.txt")
# 高さを重みに割り当てる骨（下から順に）
SPINE_BONES = ["Hips", "Spine", "Spine1", "Spine2", "Neck"]
HEAD_BONE = "Head"

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 3:
    print("使い方: blender --background --python add_outfit.py -- <リグ済み.glb> <ポンチョ帽子.glb> <出力.glb>")
    sys.exit(1)
rig_path, outfit_path, out_path = argv[0], argv[1], argv[2]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=rig_path)

arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if arm is None:
    print("[outfit] アーマチュアが見つかりません: %s" % rig_path)
    sys.exit(1)
body_objs = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm]
if not body_objs:
    print("[outfit] アーマチュアの子のメッシュが見つかりません")
    sys.exit(1)
body = body_objs[0]
print("[outfit] リグ: %s（骨 %d）/ 素体メッシュ: %s（頂点 %d）"
      % (arm.name, len(arm.data.bones), body.name, len(body.data.vertices)))

def find_bone(suffix):
    """mixamorig:Spine1 のような名前を、末尾一致で探す"""
    for b in arm.data.bones:
        if b.name == suffix or b.name.endswith(":" + suffix) or b.name.endswith("_" + suffix):
            return b
    return None

bpy.context.view_layer.update()
chain = []
for name in SPINE_BONES:
    b = find_bone(name)
    if b is not None:
        chain.append((b.name, (arm.matrix_world @ b.head_local).z))
head_bone = find_bone(HEAD_BONE)
if not chain or head_bone is None:
    print("[outfit] 背骨か頭の骨が見つかりません: %s" % [b.name for b in arm.data.bones][:12])
    sys.exit(1)
chain.sort(key=lambda kv: kv[1])
print("[outfit] 使う骨: %s / 頭 = %s"
      % (", ".join("%s(%.3f)" % (n, z) for n, z in chain), head_bone.name))

# 素体の高さ。build_traveler.py の基準（帽子の境目 HAT_SPLIT）を今の大きさに合わせる
body_zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
body_min, body_max = min(body_zs), max(body_zs)
DESIGN_BODY_TOP = 1.3156     # build_traveler.py が出す素体の高さ（羽の突起の先まで）
try:
    with open(HEIGHT_FILE) as f:
        DESIGN_BODY_TOP = float(f.read().strip())
except Exception:
    pass
scale = (body_max - body_min) / DESIGN_BODY_TOP
hat_split_z = body_min + HAT_SPLIT * scale
print("[outfit] 素体の高さ %.4f m（設計 %.3f の %.3f 倍）→ 帽子とポンチョの境目 %.4f m"
      % (body_max - body_min, DESIGN_BODY_TOP, scale, hat_split_z))

# ---- ポンチョ・帽子を読み込み、素体に合わせて拡大縮小する
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=outfit_path)
outfit_objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
if not outfit_objs:
    print("[outfit] ポンチョ・帽子のメッシュが読めません: %s" % outfit_path)
    sys.exit(1)
bpy.ops.object.select_all(action="DESELECT")
for o in outfit_objs:
    o.select_set(True)
bpy.context.view_layer.objects.active = outfit_objs[0]
if len(outfit_objs) > 1:
    bpy.ops.object.join()
outfit = bpy.context.active_object
outfit.parent = None
# 設計の座標（靴底 = 0）から、今のリグの足元へ合わせる
outfit.scale = Vector((scale, scale, scale))
outfit.location = Vector((0.0, 0.0, body_min))
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
print("[outfit] ポンチョ+帽子: 頂点 %d" % len(outfit.data.vertices))

# ---- 骨の重みを付ける
for name, _ in chain:
    if name not in outfit.vertex_groups:
        outfit.vertex_groups.new(name=name)
if head_bone.name not in outfit.vertex_groups:
    outfit.vertex_groups.new(name=head_bone.name)

n_hat = 0
for v in outfit.data.vertices:
    z = (outfit.matrix_world @ v.co).z
    if z >= hat_split_z:
        outfit.vertex_groups[head_bone.name].add([v.index], 1.0, "REPLACE")
        n_hat += 1
        continue
    # 背骨の鎖のどこに入るかで 2 本に分けて重みを付ける
    if z <= chain[0][1]:
        outfit.vertex_groups[chain[0][0]].add([v.index], 1.0, "REPLACE")
        continue
    if z >= chain[-1][1]:
        outfit.vertex_groups[chain[-1][0]].add([v.index], 1.0, "REPLACE")
        continue
    for i in range(len(chain) - 1):
        z0, z1 = chain[i][1], chain[i + 1][1]
        if z0 <= z <= z1:
            t = 0.0 if z1 - z0 < 1e-6 else (z - z0) / (z1 - z0)
            outfit.vertex_groups[chain[i][0]].add([v.index], 1.0 - t, "REPLACE")
            outfit.vertex_groups[chain[i + 1][0]].add([v.index], t, "REPLACE")
            break
print("[outfit] 重み付け: 帽子 %d 頂点 → %s / 残り %d 頂点 → 背骨"
      % (n_hat, head_bone.name, len(outfit.data.vertices) - n_hat))

# ---- 素体と結合して 1 つのスキンメッシュにする
outfit.parent = arm
outfit.matrix_parent_inverse = arm.matrix_world.inverted()
mod = outfit.modifiers.new("Armature", "ARMATURE")
mod.object = arm
bpy.ops.object.select_all(action="DESELECT")
outfit.select_set(True)
body.select_set(True)
bpy.context.view_layer.objects.active = body
bpy.ops.object.join()
merged = bpy.context.active_object
print("[outfit] 結合後: 頂点 %d / 材質 %s"
      % (len(merged.data.vertices), [m.name for m in merged.data.materials if m]))

cloth_mats = [m.name for m in merged.data.materials if m and m.name.startswith("Cloth")]
if not cloth_mats:
    print("[outfit] 注意: 名前が Cloth で始まる材質がありません。add_cloth_bones.py が布を見つけられません")
else:
    print("[outfit] 布の材質: %s（add_cloth_bones.py がこれを探す）" % ", ".join(cloth_mats))

os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB",
                          export_yup=True, export_animations=True)
print("[outfit] 書き出し: %s" % out_path)
