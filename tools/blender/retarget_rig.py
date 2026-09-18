# 既存の Mixamo リグ（骨 + アニメ 10 本）を、本キャラの寸法に合わせ直して新しい素体に付ける。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/retarget_rig.py -- <既存リグ.glb> <新しい素体.glb> <出力.glb>
#   例: blender --background --python tools/blender/retarget_rig.py -- \
#         game/assets/traveler_mixamo.glb game/assets/traveler_body_rig.glb game/assets/traveler_rigged.glb
#
# なぜこれをやるか:
#   本来は Mixamo に本キャラを渡して自動リグを取るのが正道（docs/MIXAMO_GUIDE.md 0-b 章）。
#   ただしそれはユーザーのブラウザ操作が要る。**待たずに今のモデルをゲームで歩かせる**ために、
#   すでにある仮キャラのリグ（骨の名前も Mixamo 標準、アニメ 10 本付き）を本キャラの
#   寸法に引き伸ばして流用する。Mixamo の本番リグが来たら、こちらは不要になる。
#
# やること:
#   1. 既存リグから古いメッシュを外す（骨とアニメだけ残す）
#   2. 骨の位置を本キャラの関節位置に動かす（下の TARGETS。build_traveler.py の高さの表と同じ値）
#      **骨の向きは元のまま変えない。** アニメは「休めの姿勢からの回転」として入っているので、
#      向きを変えるとアニメの見え方がその分ずれる（実際、向きを変えたら右足が 19cm 浮いた）。
#      動かすのは「骨の付け根の位置」と「長さ」だけ。位置をずらしても回転には影響しない。
#      なので TARGETS の尻尾の値は「長さを決めるため」にだけ使い、向きには使わない
#   3. 新しい素体を読み込み、骨からの距離で重みを付ける（近い 2 本に 1/距離^2 で配分）
#   4. .glb に書き出す（アニメはそのまま）
#
# 腕について: 既存リグの休めの姿勢は「腕を 40 度開いた A ポーズ」。だから素体も
#   UCHI_ARM_ANGLE=40 で作ったもの（traveler_body_rig.glb）を渡すこと。
#   腕はポンチョに隠れて見えないので、ゲーム中は角度の違いは分からない。
import math
import os
import sys

import bpy
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 3:
    print("使い方: blender --background --python retarget_rig.py -- <既存リグ.glb> <新しい素体.glb> <出力.glb>")
    sys.exit(1)
rig_path, body_path, out_path = argv[0], argv[1], argv[2]

# ---------------------------------------------------------------- 骨の合わせ方
# **一様な拡大 + 上下移動しかしない。** これが「アニメを壊さない唯一の変形」。
#
# なぜか: Mixamo のアニメは「休めの姿勢からの回転」として入っている。
# 骨の向きや、親からのずれ方を変えると、同じ回転を掛けても手足の行き先が変わる。
#   - 試しに関節を本キャラの位置へ個別に動かしたら、右足が 6〜19cm 浮いた
#   - 一様な拡大 + 平行移動なら、向きもずれ方の比も保たれるので、見え方は元のまま
#
# 合わせる基準は 2 か所だけ。ここを合わせれば足が地面に着き、腰の高さが合う:
#   股（Hips）と 足首（Foot）。この 2 点から拡大率と上下移動を決める。
#   ほかの関節（膝・胸・首・頭）は元の比率のまま少しずれるが、
#   **見えているのはポンチョの裾から下（0.365m 以下）だけ**なので問題にならない。
#   膝は裾より上に隠れる。胴と頭はポンチョと帽子の中。
ANCHOR_HIPS = ("Hips", 0.660)      # 本キャラの股の高さ（build_traveler.py の HIP + 骨の分）
ANCHOR_FOOT = ("LeftFoot", 0.195)  # 本キャラの足首の高さ（ANKLE 0.200 の少し下）

POWER = 2.0        # 重みの配分。距離^-POWER。大きいほど硬い（関節が折れやすい）
NEAR_N = 2         # 何本の骨に配るか

# ---------------------------------------------------------------- 読み込み
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=rig_path)
arm = next((o for o in bpy.data.objects if o.type == "ARMATURE"), None)
if arm is None:
    print("[retarget] アーマチュアが見つかりません: %s" % rig_path)
    sys.exit(1)
old_meshes = [o for o in bpy.data.objects if o.type == "MESH"]
print("[retarget] 既存リグ: 骨 %d / 古いメッシュ %d 個を外す（アニメは残す）"
      % (len(arm.data.bones), len(old_meshes)))
for o in old_meshes:
    bpy.data.objects.remove(o, do_unlink=True)

n_anim = 0
if arm.animation_data and arm.animation_data.nla_tracks:
    n_anim = len(arm.animation_data.nla_tracks)
print("[retarget] アニメ %d 本" % n_anim)

# ---------------------------------------------------------------- 骨を動かす（一様な拡大 + 上下移動）
def find_bone(coll, name):
    for b in coll:
        if b.name == name or b.name.endswith(":" + name) or b.name.endswith("_" + name):
            return b
    return None

bpy.context.view_layer.update()
_hips = find_bone(arm.data.bones, ANCHOR_HIPS[0])
_foot = find_bone(arm.data.bones, ANCHOR_FOOT[0])
if _hips is None or _foot is None:
    print("[retarget] 基準の骨が見つかりません（Hips / LeftFoot）")
    sys.exit(1)
z_hips_old = (arm.matrix_world @ _hips.head_local).z
z_foot_old = (arm.matrix_world @ _foot.head_local).z
if abs(z_hips_old - z_foot_old) < 1e-4:
    print("[retarget] 基準の 2 点が同じ高さです")
    sys.exit(1)
scale = (ANCHOR_HIPS[1] - ANCHOR_FOOT[1]) / (z_hips_old - z_foot_old)
shift = ANCHOR_HIPS[1] - scale * z_hips_old
print("[retarget] 合わせ: 股 %.3f→%.3f / 足首 %.3f→%.3f  ⇒ %.4f 倍 + %.4f m 上へ"
      % (z_hips_old, ANCHOR_HIPS[1], z_foot_old, ANCHOR_FOOT[1], scale, shift))

bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode="EDIT")
inv = arm.matrix_world.inverted()

def moved_world(v_local):
    w = arm.matrix_world @ v_local
    return Vector((w.x * scale, w.y * scale, w.z * scale + shift))

rolls = {eb.name: eb.roll for eb in arm.data.edit_bones}
new_pos = {}
for eb in arm.data.edit_bones:
    new_pos[eb.name] = (moved_world(eb.head.copy()), moved_world(eb.tail.copy()))
for eb in arm.data.edit_bones:
    h, t = new_pos[eb.name]
    eb.head = inv @ h
    eb.tail = inv @ t
    eb.roll = rolls[eb.name]
bpy.ops.object.mode_set(mode="OBJECT")
bpy.context.view_layer.update()
for key in ("Hips", "LeftLeg", "LeftFoot", "LeftToeBase", "Spine2", "Neck", "Head"):
    b = find_bone(arm.data.bones, key)
    if b:
        print("[retarget]   %-12s 高さ %.3f m" % (key, (arm.matrix_world @ b.head_local).z))

# ---------------------------------------------------------------- 新しい素体を読み込む
before = set(bpy.data.objects)
bpy.ops.import_scene.gltf(filepath=body_path)
new_meshes = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
if not new_meshes:
    print("[retarget] 新しい素体のメッシュが読めません: %s" % body_path)
    sys.exit(1)
bpy.ops.object.select_all(action="DESELECT")
for o in new_meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = new_meshes[0]
if len(new_meshes) > 1:
    bpy.ops.object.join()
body = bpy.context.active_object
body.parent = None
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
zs = [(body.matrix_world @ v.co).z for v in body.data.vertices]
print("[retarget] 新しい素体: 頂点 %d / 靴底 %.4f / てっぺん %.4f"
      % (len(body.data.vertices), min(zs), max(zs)))

# ---------------------------------------------------------------- 骨からの距離で重みを付ける
bpy.context.view_layer.update()
segs = []
for b in arm.data.bones:
    h = arm.matrix_world @ b.head_local
    t = arm.matrix_world @ b.tail_local
    if (t - h).length < 1e-5:
        continue
    segs.append((b.name, h, t))

def dist_to_seg(p, a, b):
    ab = b - a
    denom = ab.dot(ab)
    u = 0.0 if denom < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / denom))
    return (p - (a + ab * u)).length

groups = {}
for name, _, _ in segs:
    groups[name] = body.vertex_groups.get(name) or body.vertex_groups.new(name=name)

for v in body.data.vertices:
    p = body.matrix_world @ v.co
    ds = sorted(((dist_to_seg(p, a, b), name) for name, a, b in segs))[:NEAR_N]
    ws = [(1.0 / max(d, 1e-4) ** POWER, name) for d, name in ds]
    total = sum(w for w, _ in ws)
    for w, name in ws:
        groups[name].add([v.index], w / total, "REPLACE")
print("[retarget] 重み付け: 骨 %d 本に、近い %d 本へ 1/距離^%.0f で配分" % (len(segs), NEAR_N, POWER))

body.parent = arm
body.matrix_parent_inverse = arm.matrix_world.inverted()
mod = body.modifiers.new("Armature", "ARMATURE")
mod.object = arm

# ---------------------------------------------------------------- 書き出し
os.makedirs(os.path.dirname(os.path.abspath(out_path)) or ".", exist_ok=True)
bpy.ops.object.select_all(action="SELECT")
bpy.ops.export_scene.gltf(filepath=out_path, use_selection=True, export_format="GLB",
                          export_yup=True, export_animations=True)
print("[retarget] 書き出し: %s" % out_path)
print("[retarget] 次: add_outfit.py でポンチョを被せ、add_cloth_bones.py で揺れの骨を入れる")
