# Mixamo の .glb に「布（マント）を揺らすための骨の鎖」を差し込む。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/add_cloth_bones.py -- <入力.glb> <出力.glb>
#   例: blender --background --python tools/blender/add_cloth_bones.py -- \
#         game/assets/traveler_mixamo.glb game/assets/traveler_cloth.glb
#
# やること:
#   1. 布（Cloth 材質）のうち、胴の骨（Hips / Spine 系）に付いている頂点 = マントを選ぶ
#      （袖は腕の骨、帽子は頭の骨、靴は足の骨に付いているので自然に除ける）
#   2. マントの裾まわりに、胴のまわりを CHAINS 等分した位置から下に垂れる骨の鎖を作る
#      （1 本の鎖は JOINTS 個の骨。親は mixamorig:Spine）
#   3. 裾に近い頂点ほど、元の骨から鎖の骨へ重みを移す（裾が一番動く）
#   4. .glb に書き出す（アニメはそのまま）
#
# Godot 側では SpringBoneSimulator3D にこの鎖を登録して揺らす（scenes/player/traveler_rig.gd）。
# 骨を足すだけなので、揺らさない設定にすれば見た目は元とほぼ同じ。
import math
import os
import sys

import bpy

CHAINS = 8          # 胴のまわりに何本の鎖を垂らすか
JOINTS = 2          # 1 本の鎖の骨の数（2 でも裾は十分に動く）
TOP_RATIO = 0.45    # マントの高さのうち、下から何割を動かすか
MAX_WEIGHT = 0.9    # 裾での鎖への重みの上限（1.0 にすると胴から切り離れて見える）
BONE_PREFIX = "Cape"
TORSO_KEYS = ("Hips", "Spine")   # この語を含む骨に付いている布 = マント

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    print("使い方: blender --background --python add_cloth_bones.py -- <入力.glb> <出力.glb>")
    sys.exit(1)
src_path, out_path = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src_path)

arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if arm is None:
    print("[cloth] アーマチュアが見つかりません")
    sys.exit(1)
mesh_objs = [o for o in bpy.data.objects if o.type == "MESH" and o.parent == arm]
if not mesh_objs:
    print("[cloth] アーマチュアの子のメッシュが見つかりません")
    sys.exit(1)
obj = mesh_objs[0]
me = obj.data
print("[cloth] メッシュ %s（頂点 %d）アーマチュア %s（骨 %d）"
      % (obj.name, len(me.vertices), arm.name, len(arm.data.bones)))

group_name = {g.index: g.name for g in obj.vertex_groups}

# ---- 1. マントの頂点を選ぶ ----
cloth_mats = [i for i, m in enumerate(me.materials) if m and m.name.startswith("Cloth")]
if not cloth_mats:
    print("[cloth] Cloth 材質が見つかりません: %s" % [m.name for m in me.materials if m])
    sys.exit(1)
cloth_verts = set()
for poly in me.polygons:
    if poly.material_index in cloth_mats:
        cloth_verts.update(poly.vertices)


def dominant_group(v):
    best, best_w = None, -1.0
    for g in v.groups:
        if g.weight > best_w:
            best, best_w = group_name.get(g.group, ""), g.weight
    return best or ""


cape = []
for i in sorted(cloth_verts):
    name = dominant_group(me.vertices[i])
    if any(k in name for k in TORSO_KEYS):
        cape.append(i)
if not cape:
    print("[cloth] 胴の骨に付いた布が見つかりません")
    sys.exit(1)

co = {i: obj.matrix_world @ me.vertices[i].co for i in cape}
z_bot = min(p.z for p in co.values())
z_cape_top = max(p.z for p in co.values())
z_top = z_bot + (z_cape_top - z_bot) * TOP_RATIO
cx = sum(p.x for p in co.values()) / len(co)
cy = sum(p.y for p in co.values()) / len(co)
print("[cloth] マント: %d 頂点 z=%.3f..%.3f → 動かすのは z<%.3f（中心 x=%.3f y=%.3f）"
      % (len(cape), z_bot, z_cape_top, z_top, cx, cy))

# ---- 2. 骨の鎖を作る ----
# 鎖ごと・高さごとの半径を、その向きにある実際の布から測る（マントの形に沿わせる）
levels = [z_top - (z_top - z_bot) * (j / JOINTS) for j in range(JOINTS + 1)]
sector = math.tau / CHAINS
radius = [[[] for _ in levels] for _ in range(CHAINS)]
for i in cape:
    p = co[i]
    if p.z > z_top:
        continue
    a = math.atan2(p.y - cy, p.x - cx) % math.tau
    ci = int(a / sector) % CHAINS
    j = min(range(len(levels)), key=lambda k: abs(levels[k] - p.z))
    radius[ci][j].append(math.hypot(p.x - cx, p.y - cy))
fallback = [
    (sum(sum(radius[c][j]) for c in range(CHAINS)) / max(sum(len(radius[c][j]) for c in range(CHAINS)), 1))
    for j in range(len(levels))
]


def ring_radius(ci, j):
    vals = radius[ci][j]
    return sum(vals) / len(vals) if vals else fallback[j]


def joint_pos(ci, j):
    a = (ci + 0.5) * sector
    r = ring_radius(ci, j)
    return (cx + math.cos(a) * r, cy + math.sin(a) * r, levels[j])


parent_bone = next((b.name for b in arm.data.bones if b.name.endswith("Spine")), None)
if parent_bone is None:
    print("[cloth] 親にする Spine の骨が見つかりません")
    sys.exit(1)

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
inv = arm.matrix_world.inverted()
chain_bones = []
for ci in range(CHAINS):
    names = []
    prev = None
    for j in range(JOINTS):
        eb = arm.data.edit_bones.new("%s%d_%d" % (BONE_PREFIX, ci, j))
        eb.head = inv @ bpy.context.scene.cursor.matrix.to_translation().__class__(joint_pos(ci, j))
        eb.tail = inv @ bpy.context.scene.cursor.matrix.to_translation().__class__(joint_pos(ci, j + 1))
        eb.parent = prev if prev is not None else arm.data.edit_bones[parent_bone]
        eb.use_connect = prev is not None
        prev = eb
        names.append(eb.name)
    chain_bones.append(names)
bpy.ops.object.mode_set(mode="OBJECT")
print("[cloth] 骨を %d 本追加（%d 本の鎖 × %d）: %s ..." % (CHAINS * JOINTS, CHAINS, JOINTS, chain_bones[0]))

for names in chain_bones:
    for n in names:
        if n not in obj.vertex_groups:
            obj.vertex_groups.new(name=n)

# ---- 3. 裾に近いほど鎖の骨へ重みを移す ----
moved = 0
for i in cape:
    p = co[i]
    if p.z > z_top:
        continue
    t = (z_top - p.z) / max(z_top - z_bot, 1e-6)
    w_cloth = min(max(t, 0.0), 1.0) ** 2 * MAX_WEIGHT
    if w_cloth < 0.01:
        continue
    moved += 1
    old = {g.group: g.weight for g in me.vertices[i].groups}
    for gi, w in old.items():
        obj.vertex_groups[gi].add([i], w * (1.0 - w_cloth), "REPLACE")
    # 向きで隣り合う 2 本の鎖に分ける（境目で折れないように）
    a = (math.atan2(p.y - cy, p.x - cx) % math.tau) / sector - 0.5
    c0 = math.floor(a)
    frac = a - c0
    # 鎖の中の上下（0 = 根本の骨、1 = 先の骨）
    s = (levels[JOINTS - 1] - p.z) / max(levels[JOINTS - 1] - z_bot, 1e-6)
    s = min(max(s, 0.0), 1.0)
    share = [1.0 - s, s] if JOINTS == 2 else None
    if share is None:   # JOINTS が 3 以上なら、高さで一番近い骨に寄せる
        share = [0.0] * JOINTS
        pos = min(max((z_top - p.z) / max(z_top - z_bot, 1e-6), 0.0), 0.999) * JOINTS
        share[int(pos)] = 1.0
    for ci, aw in ((int(c0) % CHAINS, 1.0 - frac), (int(c0 + 1) % CHAINS, frac)):
        if aw <= 0.0:
            continue
        for j in range(JOINTS):
            if share[j] > 0.0:
                obj.vertex_groups[chain_bones[ci][j]].add([i], w_cloth * aw * share[j], "REPLACE")
print("[cloth] 重みを移した頂点: %d / %d" % (moved, len(cape)))

# ---- 4. 書き出し ----
anims = [t.name for o in (arm,) if o.animation_data for t in o.animation_data.nla_tracks]
print("[cloth] アニメ %d 本: %s" % (len(anims), ", ".join(anims)))
bpy.ops.object.select_all(action="DESELECT")
arm.select_set(True)
obj.select_set(True)
bpy.context.view_layer.objects.active = arm
os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path, use_selection=True, export_format="GLB", export_yup=True,
    export_animations=True, export_animation_mode="ACTIONS", export_nla_strips=True,
    export_skins=True, export_apply=False,
)
print("[cloth] 書き出し: %s" % out_path)
