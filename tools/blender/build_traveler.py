# 本キャラ「旅人」のメッシュを Blender（bpy）で組み立てて書き出す。
#
# 基準は確定ターンアラウンド 2 枚（docs/reference/character/traveler_turnaround_*.png）と
# GAME_DESIGN.md「2. キャラクター」の寸法表・パレット。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/build_traveler.py
# 出力:
#   docs/reference/character/traveler_body.obj / .mtl … Mixamo にアップロードする（ポンチョ・帽子なし）
#   game/assets/traveler_body.glb                     … 上と同じものを確認用に
#   game/assets/traveler_outfit.glb                   … ポンチョ + 帽子（リグの後に被せる）
#   game/assets/traveler_preview.glb                  … 完成形（見た目の確認用。ゲームでは使わない）
#
# 座標: Blender は Z 上。ここでは (x, 前, 高さ) で考え、pos() で Blender 座標に直す。
#       キャラは -Z（Godot の前）を向く。キャラの右 = +X。
# 高さの基準（靴底 = 0 m。GAME_DESIGN.md の表）:
#   ブーツ 0〜0.18 / 見えている脚 0.18〜0.34 / ポンチョ 0.34〜1.18 / 目の帯 1.18〜1.28
#   つば 1.28 / 帽子の円錐 1.30〜1.60
#   ポンチョ無しの素体は 0〜1.33（頭のてっぺん）。Mixamo にはこの高さで渡す。
import math
import os
import sys

import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "game", "assets")
OBJ_DIR = os.path.join(ROOT, "docs", "reference", "character")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(OBJ_DIR, exist_ok=True)

TAU = math.tau

# ---------------------------------------------------------------- 高さの表（m）
# 確定ターンアラウンド 2 枚を画素で実測して作った表（測り方は tools/measure_reference.py）。
# 2 枚は別々に生成したので寸法が完全には揃っていないが、**目の帯（襟の上〜つばの下）がぴたり一致する**。
# そこを重ねて縮尺を決めた:
#   ポンチョ姿（全高 = 1.60 m）: 襟の上 0.705 / つばの下 0.750 → 1.128 m / 1.200 m
#   ポンチョ無し: 目 0.795〜0.834 → 同じ帯に合わせると全高 1.429 m
# 見えるシルエット（ブーツの上端・ポンチョの裾・つば・帽子）はポンチョ姿の画から、
# 中の衣装（ベスト・ベルト・半ズボン・手袋）はポンチョ無しの画から取った。
SOLE = 0.0
BOOT_TOP = 0.216            # ポンチョ姿 0.135
ANKLE = 0.200
PONCHO_HEM = 0.365          # ポンチョ姿 0.228
KNEE = 0.420
SHORTS_HEM = 0.493          # ポンチョ無し 0.345（見えている脚の上端）
HIP = 0.680
SHORTS_TOP = 0.790
BELT = 0.752                # ポンチョ無し 0.510〜0.545
VEST_HEM = 0.770            # ポンチョ無し 0.520
CHEST = 0.880
SHOULDER = 0.955
VEST_TOP = 1.000            # ポンチョ無し 0.700
NECK_BASE = 0.950
HEAD_BOTTOM = 1.000         # ポンチョ無し 0.704
EYE = 1.164                 # 目の帯の中央（1.136〜1.192）
HEAD_TOP = 1.300            # ポンチョ無し 0.960。上半分は帽子の中に入る
TUFT_TOP = 1.310            # 羽の突起の先（帽子の中にぎりぎり収まる）
PONCHO_TOP = 1.128          # 立ち襟の上端 = 目の帯の下端
BRIM = 1.200                # つばの下端 = 目の帯の上端
HAT_CONE_BASE = 1.205
HAT_TIP = 1.600

# 太さの表（実測の「幅 / 身長」× 身長 の半分）
HEAD_R = 0.138              # 一番太いところ（帽子の中）
COLLAR_R = 0.150            # ポンチョ姿 0.185 → 直径 0.296
BRIM_R = 0.236              # ポンチョ姿 0.283 → 直径 0.453（縁の反りの分だけ大きめ）
HAT_BASE_R = 0.152          # ポンチョ姿 0.190 → 直径 0.304
HEM_R = 0.298               # 一番太いところ（裾の少し上）。裾そのものは 0.290
LEG_X = 0.120               # 見えている脚の外側の広がり 0.182 → 直径 0.29
BOOT_W = 0.224              # ブーツ 1 足の幅。足元の幅が 0.285 × 1.6 = 0.456 m になるように

BODY_HEIGHT = TUFT_TOP          # Mixamo に渡す姿の高さ
FULL_HEIGHT = HAT_TIP           # 帽子まで入れた設計上の身長

# ここでの +X は「正面から見て右」＝ **キャラの左**（.glb は +Z が前になるため）。
# 胸のボタンは「正面から見て左（キャラの右胸）」なので -X 側に置く。

# ---------------------------------------------------------------- 材質（パレットは docs/reference/character/README.md）
def srgb(hex_str):
    """#RRGGBB → Blender の Base Color（リニア）"""
    h = hex_str.lstrip("#")
    out = []
    for i in range(0, 6, 2):
        c = int(h[i:i + 2], 16) / 255.0
        out.append(c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4)
    return tuple(out)

def make_material(name, hex_str, roughness=0.9):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*srgb(hex_str), 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat

bpy.ops.wm.read_factory_settings(use_empty=True)

MAT_BODY = make_material("Body", "#2E2D2B")        # 確定色 #3A3937 より少し黒く（README の指示）
MAT_EYE = make_material("Eye", "#F2EDE3", 0.5)
MAT_BOOT = make_material("Boot", "#665C51")
MAT_BUTTON = make_material("Button", "#877A6A", 0.6)
MAT_VEST = make_material("Vest", "#C4B098")
MAT_GLOVE = make_material("Glove", "#DBCBB9")
MAT_SHORTS = make_material("Shorts", "#9C8970")
MAT_LEATHER = make_material("Leather", "#6C5747", 0.7)
# 布（帽子・ポンチョ）。add_cloth_bones.py は名前が Cloth で始まる材質を「布」として探す
MAT_CLOTH = make_material("Cloth", "#BAA990")

# ---------------------------------------------------------------- 組み立ての道具
group = []   # いま作っているパーツの入れ物

def pos(x, forward, up):
    """(x, 前, 高さ) → Blender 座標。前は -Y。"""
    return Vector((x, -forward, up))

def add(obj, mat):
    obj.data.materials.append(mat)
    group.append(obj)
    return obj

def sphere(name, radius, at, mat, scale=(1.0, 1.0, 1.0), segments=14, rings=8):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=segments, ring_count=rings, location=at)
    o = bpy.context.active_object
    o.name = name
    o.scale = Vector(scale)
    return add(o, mat)

def capsule(name, radius, start, end, mat, segments=12, caps=True):
    start = Vector(start); end = Vector(end)
    axis = end - start
    mid = (start + end) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=max(axis.length, 0.001), vertices=segments, location=mid)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(axis.normalized())
    add(o, mat)
    if caps:
        sphere(name + "_a", radius, start, mat, segments=segments, rings=6)
        sphere(name + "_b", radius, end, mat, segments=segments, rings=6)
    return o

def box(name, size, at, mat, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    o = bpy.context.active_object
    o.name = name
    o.scale = Vector(size)
    o.rotation_euler = rot
    return add(o, mat)

def lathe(name, profile, mat, segs=22, a0=0.0, a1=TAU, depth=1.0,
          wave=0.0, wave_n=3, thickness=0.0, cap_top=False, cap_bottom=False, x_off=0.0, tilt=0.0):
    """profile = [(高さ, 半径, 前へのずれ), ...] を縦軸のまわりに回す。
    a=0 が前（+前）、a が増えるとキャラの右（+X）へ回る。"""
    closed = abs((a1 - a0) - TAU) < 1e-6
    n_ring = segs if closed else segs + 1
    verts, faces = [], []
    for (h, r, fwd) in profile:
        for i in range(n_ring):
            a = a0 + (a1 - a0) * (i / segs)
            rr = r * (1.0 + wave * math.sin(wave_n * a)) if wave else r
            dh = tilt * math.cos(a) * (rr / max(profile[-1][1], 1e-6))   # 前（a=0）ほど下がる
            verts.append(pos(x_off + rr * math.sin(a), rr * math.cos(a) * depth + fwd, h + dh))
    rings = len(profile)
    for j in range(rings - 1):
        for i in range(n_ring if closed else n_ring - 1):
            i2 = (i + 1) % n_ring
            a = j * n_ring + i
            b = j * n_ring + i2
            c = (j + 1) * n_ring + i2
            d = (j + 1) * n_ring + i
            faces.append((a, b, c, d))
    if cap_bottom and closed:
        verts.append(pos(x_off, profile[0][2], profile[0][0]))
        ci = len(verts) - 1
        for i in range(n_ring):
            faces.append((ci, (i + 1) % n_ring, i))
    if cap_top and closed:
        verts.append(pos(x_off, profile[-1][2], profile[-1][0]))
        ci = len(verts) - 1
        base = (rings - 1) * n_ring
        for i in range(n_ring):
            faces.append((ci, base + i, base + (i + 1) % n_ring))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    if thickness:
        mod = o.modifiers.new("Solidify", "SOLIDIFY")
        mod.thickness = thickness
        mod.offset = 0.0
    return add(o, mat)

def button(name, at, radius, mat, facing="forward", thickness=0.012):
    """穴が 2 つ空いた丸ボタン。布から少しだけ盛り上がるドーム型にする
    （円盤にすると真横から見たとき棘のように突き出て見えるため）。"""
    flat = max(thickness / radius, 0.05)
    if facing == "forward":
        scale = (1.0, flat, 1.0)
        out = Vector((0, -thickness * 0.85, 0))     # 前 = -Y
    else:
        scale = (1.0, 1.0, flat)
        out = Vector((0, 0, thickness * 0.85))
    sphere(name, radius, at, mat, scale=scale, segments=16, rings=8)
    for s_ in (-1.0, 1.0):
        hole_at = Vector(at) + Vector((s_ * radius * 0.34, 0, 0)) + out
        sphere(name + "_hole%d" % (1 if s_ < 0 else 2), radius * 0.17, hole_at, MAT_BODY,
               scale=(1.0, flat * 1.2, 1.0) if facing == "forward" else (1.0, 1.0, flat * 1.2),
               segments=8, rings=6)
    return None


def stack(name, rings, mat, segs=18, x_off=0.0, cap=True):
    """rings = [(高さ, 横半径, 前後半径, 前へのずれ), ...] を積んだ筒。ブーツのような形に使う。"""
    verts, faces = [], []
    for (h, rx, ry, fwd) in rings:
        for i in range(segs):
            a = TAU * i / segs
            verts.append(pos(x_off + rx * math.sin(a), ry * math.cos(a) + fwd, h))
    for j in range(len(rings) - 1):
        for i in range(segs):
            i2 = (i + 1) % segs
            faces.append((j * segs + i, j * segs + i2, (j + 1) * segs + i2, (j + 1) * segs + i))
    if cap:
        verts.append(pos(x_off + rings[0][3] * 0.0, rings[0][3], rings[0][0]))
        ci = len(verts) - 1
        for i in range(segs):
            faces.append((ci, (i + 1) % segs, i))
        verts.append(pos(x_off, rings[-1][3], rings[-1][0]))
        ci = len(verts) - 1
        base = (len(rings) - 1) * segs
        for i in range(segs):
            faces.append((ci, base + i, base + (i + 1) % segs))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    return add(o, mat)

def finish(objs, name):
    """パーツをまとめて 1 つのメッシュにする"""
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.convert(target="MESH")      # モディファイアを適用
    bpy.ops.object.join()
    o = bpy.context.active_object
    o.name = name
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
    bpy.ops.object.shade_smooth()
    return o

# ================================================================ 素体（Mixamo に渡す姿）
group = []

# ---- 頭（卵型。上が太く、下があごに向かって細る。上半分は帽子の中に入る）
HEAD_PROFILE = [
    (1.000, 0.000, 0.0), (1.012, 0.055, 0.0), (1.036, 0.090, 0.0), (1.066, 0.112, 0.0),
    (1.100, 0.128, 0.0), (1.135, 0.136, 0.0), (1.170, 0.138, 0.0), (1.205, 0.134, 0.0),
    (1.240, 0.123, 0.0), (1.272, 0.098, 0.0), (1.292, 0.058, 0.0), (1.300, 0.000, 0.0),
]
lathe("Head", HEAD_PROFILE, MAT_BODY, segs=22, depth=0.94)
# 首（細い。2026-09-17 の変更）
capsule("Neck", 0.032, pos(0, 0, NECK_BASE - 0.015), pos(0, 0, HEAD_BOTTOM + 0.045), MAT_BODY, segments=10, caps=False)
# 頭頂部の後ろの羽のような突起（形で作る。帽子を被るとほぼ隠れる長さ）
for i, (dx, length, ang, w) in enumerate([(-0.025, 0.044, 55.0, 0.011), (0.002, 0.053, 48.0, 0.013), (0.028, 0.040, 62.0, 0.010)]):
    base = pos(dx, -0.030, 1.240)
    t = math.radians(ang)
    tip = base + Vector((dx * 0.3, math.sin(t) * length, math.cos(t) * length))
    capsule("Tuft%d" % i, w, base, tip, MAT_BODY, segments=6, caps=False)
    sphere("TuftTip%d" % i, w * 0.4, tip, MAT_BODY, segments=6, rings=4)
# 目（縦長の楕円。目の帯 1.136〜1.192 に収める）
for sx in (-1.0, 1.0):
    sphere("Eye%s" % ("R" if sx < 0 else "L"), 0.033, pos(sx * 0.052, 0.116, EYE), MAT_EYE,
           scale=(0.70, 0.40, 0.95), segments=12, rings=8)

# ---- 胴（黒）
lathe("Torso", [
    (HIP - 0.03, 0.094, 0.0), (0.76, 0.091, 0.0), (CHEST, 0.093, 0.0),
    (SHOULDER, 0.086, 0.0), (SHOULDER + 0.030, 0.062, 0.0),
], MAT_BODY, segs=18, depth=0.86, cap_top=True, cap_bottom=True)

# ---- ベスト（袖なし・折り襟・ボタン 3 つ）。前を V に開ける
VEST_RINGS = [(VEST_HEM, 0.100), (0.82, 0.106), (0.88, 0.109), (0.94, 0.107), (VEST_TOP, 0.092)]
segs = 22
verts, faces = [], []
for j, (h, r) in enumerate(VEST_RINGS):
    for i in range(segs):
        a_ = TAU * i / segs
        front = max(0.0, math.cos(a_)) ** 1.2
        dip = (0.080 if j == len(VEST_RINGS) - 1 else 0.032 if j == len(VEST_RINGS) - 2 else 0.0) * front
        verts.append(pos(r * math.sin(a_), r * math.cos(a_) * 0.88, h - dip))
for j in range(len(VEST_RINGS) - 1):
    for i in range(segs):
        i2 = (i + 1) % segs
        faces.append((j * segs + i, j * segs + i2, (j + 1) * segs + i2, (j + 1) * segs + i))
mesh = bpy.data.meshes.new("Vest")
mesh.from_pydata(verts, [], faces)
mesh.update()
vest = bpy.data.objects.new("Vest", mesh)
bpy.context.collection.objects.link(vest)
mod = vest.modifiers.new("Solidify", "SOLIDIFY")
mod.thickness = 0.013
mod.offset = 1.0
add(vest, MAT_VEST)
# 折り襟: 前の V のところだけ開けて、肩から後ろをぐるりと一周
lathe("VestCollar", [(0.962, 0.102, 0.0), (0.996, 0.112, 0.0), (1.012, 0.124, 0.0)], MAT_VEST,
      segs=20, a0=math.radians(34.0), a1=math.radians(326.0), depth=0.88, thickness=0.011)
# ボタン 3 つ（前の中央。ポンチョ無しの画の 0.540 / 0.577 / 0.616 に対応）
for h in (0.772, 0.825, 0.878):
    button("VestButton_%d" % int(h * 1000), pos(0, 0.100, h), 0.011, MAT_BUTTON, thickness=0.005)

# ---- ベルト（バックル付き）
lathe("Belt", [(BELT - 0.021, 0.106, 0.0), (BELT + 0.021, 0.106, 0.0)], MAT_LEATHER,
      segs=20, depth=0.88, thickness=0.011)
box("Buckle", (0.038, 0.011, 0.034), pos(0, 0.098, BELT), MAT_BUTTON)

# ---- 半ズボン（腰 → 太もも半ば。裾を折り返す）
lathe("Shorts", [(0.62, 0.107, 0.0), (0.70, 0.108, 0.0), (SHORTS_TOP, 0.102, 0.0)], MAT_SHORTS,
      segs=20, depth=0.90, thickness=0.013)
def leg_x(sx, h):
    t = max(0.0, min(1.0, (HIP - h) / (HIP - KNEE)))
    return sx * (0.050 + (0.088 - 0.050) * t)
for sx in (-1.0, 1.0):
    tag = "L" if sx > 0 else "R"
    lathe("ShortsLeg%s" % tag, [(SHORTS_HEM + 0.032, 0.054, 0.0), (0.625, 0.059, 0.0)], MAT_SHORTS,
          segs=12, x_off=leg_x(sx, 0.56), thickness=0.012)
    lathe("ShortsCuff%s" % tag, [(SHORTS_HEM, 0.062, 0.0), (SHORTS_HEM + 0.034, 0.062, 0.0)], MAT_SHORTS,
          segs=12, x_off=leg_x(sx, 0.51), thickness=0.012)

# ---- 腰の後ろの鞄（柔らかい袋）
bag_at = pos(0.050, -0.110, 0.690)
sphere("Bag", 0.060, bag_at, MAT_LEATHER, scale=(0.88, 0.58, 0.96), segments=12, rings=8)
box("BagFlap", (0.088, 0.044, 0.030), bag_at + Vector((0, -0.008, 0.050)), MAT_LEATHER)
box("BagStrap", (0.022, 0.046, 0.058), bag_at + Vector((0, 0.024, 0.046)), MAT_LEATHER)

# ---- 腕（A ポーズ）と手袋（5 本指）。ポンチョの中に収まる長さ・角度にする
ARM_ANGLE = math.radians(21.0)
UPPER_ARM, FORE_ARM = 0.163, 0.138
for sx in (-1.0, 1.0):
    tag = "L" if sx > 0 else "R"
    sh = pos(sx * 0.070, 0, SHOULDER - 0.015)
    d = Vector((sx * math.sin(ARM_ANGLE), 0, -math.cos(ARM_ANGLE)))
    el = sh + d * UPPER_ARM
    wr = el + d * FORE_ARM
    sphere("Shoulder%s" % tag, 0.037, sh, MAT_BODY, segments=10, rings=6)
    capsule("UpperArm%s" % tag, 0.027, sh, el, MAT_BODY, segments=10)
    capsule("ForeArm%s" % tag, 0.024, el, wr, MAT_BODY, segments=10)
    # 手袋: カフス → 手のひら → 5 本指
    capsule("GloveCuff%s" % tag, 0.036, wr - d * 0.008, wr + d * 0.038, MAT_GLOVE, segments=12, caps=False)
    palm_c = wr + d * 0.072
    sphere("GlovePalm%s" % tag, 0.040, palm_c, MAT_GLOVE, scale=(1.0, 0.60, 1.0), segments=12, rings=8)
    side = Vector((d.z, 0, -d.x)).normalized()     # 腕に直交する水平方向
    for k, (off, length) in enumerate([(-0.025, 0.040), (-0.009, 0.045), (0.009, 0.042), (0.024, 0.035)]):
        root = palm_c + side * (off * sx) + Vector((0, 0.006, 0))
        capsule("Finger%s%d" % (tag, k), 0.0097, root, root + d * length, MAT_GLOVE, segments=6)
    th_root = palm_c + side * (-0.033 * sx) - d * 0.012
    th_tip = th_root + (d * 0.025 + side * (-0.023 * sx) + Vector((0, 0.010, 0)))
    capsule("Thumb%s" % tag, 0.0105, th_root, th_tip, MAT_GLOVE, segments=6)

# ---- 脚（黒。細い）とブーツ（大きい）
for sx in (-1.0, 1.0):
    tag = "L" if sx > 0 else "R"
    hip = pos(sx * 0.050, 0, HIP)
    knee = pos(sx * 0.088, 0, KNEE)
    ankle = pos(sx * LEG_X, 0, ANKLE)
    capsule("Thigh%s" % tag, 0.031, hip, knee, MAT_BODY, segments=10)
    capsule("Shin%s" % tag, 0.028, knee, ankle, MAT_BODY, segments=10)
    bx = sx * LEG_X
    # 筒（脚を包む）+ 折り返しのカフス
    # ブーツ: 底 → つま先の膨らみ → 足首 → 折り返しのカフス を 1 つの筒で作る
    stack("Boot%s" % tag, [
        (0.000, 0.095, 0.104, 0.032),
        (0.020, 0.108, 0.124, 0.032),
        (0.055, 0.112, 0.128, 0.028),
        (0.090, 0.098, 0.104, 0.014),
        (0.128, 0.072, 0.075, 0.000),
        (0.158, 0.068, 0.068, -0.006),
        (0.162, 0.076, 0.076, -0.006),
        (BOOT_TOP, 0.073, 0.073, -0.006),
    ], MAT_BOOT, segs=20, x_off=bx)

body_parts = list(group)
body = finish(body_parts, "TravelerBody")
print("[traveler] 素体: 頂点 %d / 面 %d" % (len(body.data.vertices), len(body.data.polygons)))

# ================================================================ ポンチョ + 帽子（リグの後に被せる）
group = []

# ---- ポンチョ（立ち襟 → テント型の裾）
# 半径は「ポンチョ姿の画の幅 × 1.60 ÷ 2」。0.4〜0.64 のあたりが太すぎたので測り直して入れた
PONCHO_PROFILE = [
    (PONCHO_TOP, 0.148, 0.0), (1.090, 0.144, 0.0), (1.060, 0.145, 0.0), (1.024, 0.148, 0.0),
    (0.960, 0.164, 0.0), (0.896, 0.182, 0.0), (0.832, 0.197, 0.0), (0.768, 0.214, 0.0),
    (0.704, 0.230, 0.0), (0.640, 0.247, 0.0), (0.576, 0.265, 0.0), (0.512, 0.282, 0.0),
    (0.448, 0.297, 0.0), (0.400, 0.298, 0.0), (PONCHO_HEM, 0.290, 0.0),
]
lathe("Poncho", PONCHO_PROFILE, MAT_CLOTH, segs=26, depth=0.93, thickness=0.013)
# 裾が少し波打つ縁取り
lathe("PonchoHem", [(PONCHO_HEM + 0.030, 0.296, 0.0), (PONCHO_HEM, 0.291, 0.0)], MAT_CLOTH,
      segs=26, depth=0.93, wave=0.018, wave_n=7, thickness=0.014)
# 立ち襟の折り返し（顔の下半分を隠す帯。基準画像でははっきり見える）
lathe("PonchoCollar", [(1.052, 0.152, 0.0), (1.090, 0.159, 0.0), (PONCHO_TOP, 0.161, 0.0)], MAT_CLOTH,
      segs=26, depth=0.93, thickness=0.012)
# 前の重ね合わせ（キャラの右の前身頃が左へ被さる。合わせ目が裾まで通る）
flap = [(h, r * 1.040, f) for (h, r, f) in PONCHO_PROFILE[4:]]
lathe("PonchoFlap", flap, MAT_CLOTH, segs=12,
      a0=math.radians(32.0), a1=math.radians(-102.0), depth=0.93, thickness=0.011)
# 胸の大きなボタン（正面から見て左 = キャラの右胸 = -X）
button("PonchoButton", pos(-0.076, 0.150, 1.020), 0.028, MAT_BUTTON, thickness=0.011)

# ---- 帽子（短い反り上がったつば + 背の高い円錐 + 丸ボタン）
lathe("HatBrim", [(1.216, 0.104, 0.0), (BRIM - 0.006, 0.150, 0.0), (BRIM + 0.002, 0.198, 0.0), (1.218, 0.236, 0.0), (1.234, 0.230, 0.0)],
      MAT_CLOTH, segs=26, thickness=0.008, tilt=-0.022)
# 円錐は先端がわずかに後ろへ傾く（まっすぐな針にしない）
cone_rings = []
for i in range(11):
    t = i / 10.0
    h = HAT_CONE_BASE + t * (HAT_TIP - HAT_CONE_BASE)
    r = HAT_BASE_R * (1.0 - t) ** 0.98
    cone_rings.append((h, max(r, 0.0), -0.145 * (t ** 1.6)))     # 後ろ = -前。先端ほど後ろへ反る
lathe("HatCone", cone_rings, MAT_CLOTH, segs=20, cap_bottom=True)
button("HatButton", pos(0.0, 0.089, 1.330), 0.027, MAT_BUTTON, thickness=0.010)

outfit_parts = list(group)
outfit = finish(outfit_parts, "TravelerOutfit")
print("[traveler] ポンチョ+帽子: 頂点 %d / 面 %d" % (len(outfit.data.vertices), len(outfit.data.polygons)))

# ================================================================ 書き出し
def select_only(objs):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]

def check_height(obj, expected, label):
    zs = [(obj.matrix_world @ v.co).z for v in obj.data.vertices]
    h = max(zs) - min(zs)
    print("[traveler] %s: 靴底 %.4f m / てっぺん %.4f m / 高さ %.4f m（設計 %.3f m）"
          % (label, min(zs), max(zs), h, expected))
    return h

body_h = check_height(body, BODY_HEIGHT, "素体（Mixamo に渡す姿）")
check_height(outfit, FULL_HEIGHT - PONCHO_HEM, "ポンチョ+帽子")
# Mixamo から戻ってきたモデルをこの高さに正規化する（mixamo_fbx_to_glb.py の第 3 引数）
with open(os.path.join(OBJ_DIR, "traveler_body_height.txt"), "w") as f:
    f.write("%.4f\n" % body_h)
print("[traveler] Mixamo 変換に渡す身長: %.4f m（traveler_body_height.txt に保存）" % body_h)

select_only([body])
obj_path = os.path.join(OBJ_DIR, "traveler_body.obj")
bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=True,
                      forward_axis="NEGATIVE_Z", up_axis="Y", export_materials=True)
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "traveler_body.glb"),
                          use_selection=True, export_format="GLB", export_yup=True)

select_only([outfit])
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "traveler_outfit.glb"),
                          use_selection=True, export_format="GLB", export_yup=True)

select_only([body, outfit])
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT_DIR, "traveler_preview.glb"),
                          use_selection=True, export_format="GLB", export_yup=True)

print("[traveler] 書き出し: %s / traveler_body.glb / traveler_outfit.glb / traveler_preview.glb" % obj_path)
