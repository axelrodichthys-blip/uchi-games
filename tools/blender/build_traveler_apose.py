# 仮キャラ「旅人」の A ポーズのメッシュを Blender（bpy）で組み立てて書き出す。
# Mixamo の自動リグに渡す用（OBJ）と、確認用（GLB）。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/build_traveler_apose.py
# 出力:
#   docs/reference/character/traveler_apose.obj / .mtl … Mixamo にアップロードする
#   game/assets/traveler_apose.glb                     … Godot で形を確認する用
#
# 寸法は game/scenes/player/traveler.gd と揃えている（身長 約1.62m、Y が上、-Z が前）。
import math
import os
import bpy
from mathutils import Vector

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", ".."))
OUT_DIR = os.path.join(ROOT, "game", "assets")
OBJ_DIR = os.path.join(ROOT, "docs", "reference", "character")
os.makedirs(OUT_DIR, exist_ok=True)
os.makedirs(OBJ_DIR, exist_ok=True)

# Blender は Z が上。Godot / Mixamo の Y 上には書き出し時に変換する。
# ここでは (x, 前後, 高さ) で考え、Blender 座標 (x, -前, 高さ) に置く。
ANKLE_H = 0.08
SHIN = 0.40
THIGH = 0.42
HIP_W = 0.10
SPINE_L = 0.10
CHEST_L = 0.16
NECK_L = 0.12
HEAD_R = 0.15
SHOULDER_W = 0.19
UPPER_ARM = 0.28
FORE_ARM = 0.26
COAT_LENGTH = 0.62
HIPS_Y = THIGH + SHIN + ANKLE_H - 0.02
ARM_ANGLE = math.radians(40.0)  # A ポーズ: 腕を体から 40 度開く

# 空のシーンから始める（材質より前にやること。後でやるとデータが消える）
bpy.ops.wm.read_factory_settings(use_empty=True)

# ---------------------------------------------------------------- 材質
def make_material(name, rgb):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat

MAT_BODY = make_material("Body", (0.07, 0.07, 0.08))
MAT_CLOTH = make_material("Cloth", (0.83, 0.74, 0.58))
MAT_EYE = make_material("Eye", (1.0, 1.0, 1.0))

parts = []

def pos(x, forward, up):
    """(x, 前, 高さ) → Blender 座標。前は -Y。"""
    return Vector((x, -forward, up))

def add(obj, mat):
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj

def sphere(name, radius, at, mat):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=radius, segments=16, ring_count=10, location=at)
    o = bpy.context.active_object
    o.name = name
    return add(o, mat)

def capsule(name, radius, length, start, end, mat):
    """start → end を結ぶカプセル（円柱 + 両端の球）"""
    start = Vector(start); end = Vector(end)
    axis = end - start
    mid = (start + end) * 0.5
    bpy.ops.mesh.primitive_cylinder_add(radius=radius, depth=max(axis.length, 0.01), vertices=14, location=mid)
    o = bpy.context.active_object
    o.name = name
    o.rotation_mode = "QUATERNION"
    o.rotation_quaternion = Vector((0, 0, 1)).rotation_difference(axis.normalized())
    add(o, mat)
    sphere(name + "_a", radius, start, mat)
    sphere(name + "_b", radius, end, mat)
    return o

def box(name, size, at, mat):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=at)
    o = bpy.context.active_object
    o.name = name
    o.scale = Vector(size)
    return add(o, mat)

def cone(name, r_bottom, r_top, height, at, mat, tilt=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(radius1=r_bottom, radius2=r_top, depth=height, vertices=16, location=at)
    o = bpy.context.active_object
    o.name = name
    o.rotation_euler = tilt
    return add(o, mat)

def coat_half(name, left, mat):
    """腰の周りを後ろ中心に覆う円錐台の帯。前が開く。"""
    segments = 8
    top_r, bottom_r = 0.19, 0.34
    a0 = math.radians(90.0)
    a1 = math.radians(215.0) if left else math.radians(-35.0)
    verts, faces = [], []
    for i in range(segments + 1):
        a = a0 + (a1 - a0) * i / segments
        # 帯の角度: Godot 側と同じく +Z(後ろ) が 90 度。Blender では後ろ = +Y
        verts.append(pos(math.cos(a) * top_r, -math.sin(a) * top_r, HIPS_Y))
        verts.append(pos(math.cos(a) * bottom_r, -math.sin(a) * bottom_r, HIPS_Y - COAT_LENGTH))
    for i in range(segments):
        t0, b0, t1, b1 = 2 * i, 2 * i + 1, 2 * i + 2, 2 * i + 3
        faces.append((t0, b0, b1, t1))
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.update()
    o = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(o)
    # 厚みを付ける（片面だと Mixamo が嫌がることがある）
    mod = o.modifiers.new("Solidify", "SOLIDIFY")
    mod.thickness = 0.02
    return add(o, mat)

# ---------------------------------------------------------------- 組み立て
# 骨盤〜胸
sphere("Pelvis", 0.15, pos(0, 0, HIPS_Y + 0.02), MAT_CLOTH)
capsule("Torso", 0.15, 0, pos(0, 0, HIPS_Y + 0.05), pos(0, 0, HIPS_Y + SPINE_L + CHEST_L + 0.06), MAT_CLOTH)
chest_top = HIPS_Y + SPINE_L + CHEST_L
sphere("Collar", 0.075, pos(0, 0, chest_top + NECK_L * 0.6), MAT_BODY)
# 頭・目
head_c = chest_top + NECK_L + 0.05 + HEAD_R
sphere("Head", HEAD_R, pos(0, 0, head_c), MAT_BODY)
sphere("EyeL", 0.028, pos(-0.055, HEAD_R - 0.02, head_c + 0.02), MAT_EYE)
sphere("EyeR", 0.028, pos(0.055, HEAD_R - 0.02, head_c + 0.02), MAT_EYE)
# 帽子
brim_z = head_c - HEAD_R + HEAD_R * 1.65
cone("HatBrim", 0.30, 0.30, 0.025, pos(0, 0, brim_z), MAT_CLOTH)
cone("HatCone", 0.18, 0.0, 0.52, pos(0, 0, brim_z + 0.26), MAT_CLOTH, tilt=(math.radians(6.0), math.radians(-9.0), 0))

# 腕（A ポーズ）
for sx in (-1.0, 1.0):
    sh = pos(sx * SHOULDER_W, 0, chest_top + 0.10)
    d = Vector((sx * math.sin(ARM_ANGLE), 0, -math.cos(ARM_ANGLE)))
    el = sh + d * UPPER_ARM
    wr = el + d * FORE_ARM
    sphere("Shoulder%s" % ("L" if sx < 0 else "R"), 0.075, sh, MAT_CLOTH)
    capsule("UpperArm%s" % ("L" if sx < 0 else "R"), 0.058, 0, sh, el, MAT_CLOTH)
    capsule("ForeArm%s" % ("L" if sx < 0 else "R"), 0.052, 0, el, wr, MAT_CLOTH)
    sphere("Hand%s" % ("L" if sx < 0 else "R"), 0.06, wr + d * 0.05, MAT_BODY)

# 脚（少し開く）
for sx in (-1.0, 1.0):
    hip = pos(sx * HIP_W, 0, HIPS_Y)
    knee = pos(sx * (HIP_W + 0.02), 0, HIPS_Y - THIGH)
    ankle = pos(sx * (HIP_W + 0.04), 0, ANKLE_H)
    capsule("Thigh%s" % ("L" if sx < 0 else "R"), 0.075, 0, hip, knee, MAT_BODY)
    capsule("Shin%s" % ("L" if sx < 0 else "R"), 0.062, 0, knee, ankle, MAT_BODY)
    box("Foot%s" % ("L" if sx < 0 else "R"), (0.10, 0.24, ANKLE_H), pos(sx * (HIP_W + 0.04), 0.05, ANKLE_H * 0.5), MAT_BODY)

# コート
coat_half("CoatL", True, MAT_CLOTH)
coat_half("CoatR", False, MAT_CLOTH)

# ---------------------------------------------------------------- 結合して書き出し
bpy.ops.object.select_all(action="DESELECT")
for o in parts:
    o.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.convert(target="MESH")  # モディファイアを適用
bpy.ops.object.join()
traveler = bpy.context.active_object
traveler.name = "Traveler"
bpy.ops.object.transform_apply(location=True, rotation=True, scale=True)
bpy.ops.object.shade_smooth()

print("[traveler] 頂点数: %d 面数: %d" % (len(traveler.data.vertices), len(traveler.data.polygons)))

obj_path = os.path.join(OBJ_DIR, "traveler_apose.obj")
bpy.ops.wm.obj_export(filepath=obj_path, export_selected_objects=True, forward_axis="NEGATIVE_Z", up_axis="Y", export_materials=True)
glb_path = os.path.join(OUT_DIR, "traveler_apose.glb")
bpy.ops.export_scene.gltf(filepath=glb_path, use_selection=True, export_format="GLB", export_yup=True)
print("[traveler] 書き出し: %s, %s" % (obj_path, glb_path))
