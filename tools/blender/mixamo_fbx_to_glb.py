# Mixamo からダウンロードした FBX（複数）を 1 つの .glb にまとめる。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/mixamo_fbx_to_glb.py -- <FBXのフォルダ> <出力.glb> [身長m]
#   例: blender --background --python tools/blender/mixamo_fbx_to_glb.py -- docs/reference/mixamo game/assets/traveler_mixamo.glb
#
# 前提:
#   - フォルダ内に「With Skin」でダウンロードした FBX が 1 つ以上ある（メッシュ + リグ + アニメ）
#   - 残りは「Without Skin」（リグ + アニメだけ）でよい
#   - ファイル名がそのままアニメ名になる（例: Walking.fbx → "Walking"）
# 出来上がる .glb は Godot にそのまま読み込める（AnimationPlayer にアニメが並ぶ）。
import os
import sys
import bpy

argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
if len(argv) < 2:
    print("使い方: blender --background --python mixamo_fbx_to_glb.py -- <FBXのフォルダ> <出力.glb>")
    sys.exit(1)
src_dir, out_path = argv[0], argv[1]

bpy.ops.wm.read_factory_settings(use_empty=True)

fbx_files = sorted(f for f in os.listdir(src_dir) if f.lower().endswith(".fbx"))
if not fbx_files:
    print("FBX が見つかりません: %s" % src_dir)
    sys.exit(1)

base_armature = None
base_mesh_objects = []
actions = []

for name in fbx_files:
    path = os.path.join(src_dir, name)
    before = set(bpy.data.objects)
    bpy.ops.import_scene.fbx(filepath=path, automatic_bone_orientation=False, ignore_leaf_bones=True)
    new_objects = [o for o in bpy.data.objects if o not in before]
    armatures = [o for o in new_objects if o.type == "ARMATURE"]
    meshes = [o for o in new_objects if o.type == "MESH"]
    if not armatures:
        print("[mixamo] アーマチュアが無いので飛ばします: %s" % name)
        continue
    arm = armatures[0]
    action = arm.animation_data.action if arm.animation_data else None
    anim_name = os.path.splitext(name)[0]
    if action:
        action.name = anim_name
        action.use_fake_user = True
        actions.append(action)
        print("[mixamo] 読み込み: %s（%d フレーム）" % (anim_name, int(action.frame_range[1] - action.frame_range[0])))
    if base_armature is None and meshes:
        base_armature = arm
        # アーマチュアの子（スキン付き）だけを使う。親の無いコピーは捨てる
        base_mesh_objects = [m for m in meshes if m.parent == arm] or meshes
        for m in meshes:
            if m not in base_mesh_objects:
                bpy.data.objects.remove(m, do_unlink=True)
        base_armature.name = "Traveler"
    else:
        # 骨だけの FBX は、アクションを取り出したら削除する
        for o in new_objects:
            bpy.data.objects.remove(o, do_unlink=True)

if base_armature is None:
    print("[mixamo] 「With Skin」の FBX（メッシュ入り）が 1 つ必要です")
    sys.exit(1)

# すべてのアクションを NLA トラックに並べて、glTF に全部入るようにする
if base_armature.animation_data is None:
    base_armature.animation_data_create()
base_armature.animation_data.action = None
for action in actions:
    track = base_armature.animation_data.nla_tracks.new()
    track.name = action.name
    track.strips.new(action.name, int(action.frame_range[0]), action)

# 大きさを設定書どおりに揃える。Mixamo は単位を cm と解釈するので、そのままだと 100 倍ずれる。
# 身長は **帽子の先まで 1.6 m**（2026-09-17 決定。GAME_DESIGN.md「キャラクター」）。
# 参照 OBJ はここでは材質の復元にだけ使い、高さの基準にはしない（OBJ は 2.07m で作ってあるため）。
REF_OBJ = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "reference", "character", "traveler_apose.obj")
TARGET_HEIGHT = 1.6  # 帽子の先まで m。第 3 引数で上書きできる
if len(argv) >= 3:
    TARGET_HEIGHT = float(argv[2])
def obj_height(path):
    zmin, zmax = None, None
    with open(path) as f:
        for line in f:
            if line.startswith("v "):
                z = float(line.split()[2])  # OBJ は Y 上なので 2 番目が高さ
                zmin = z if zmin is None else min(zmin, z)
                zmax = z if zmax is None else max(zmax, z)
    return (zmax - zmin) if zmin is not None else 0.0
print("[mixamo] 目標の身長（帽子の先まで）: %.3f m" % TARGET_HEIGHT)

def world_height(objs):
    zs = []
    for o in objs:
        for v in o.data.vertices:
            zs.append((o.matrix_world @ v.co).z)
    return (max(zs) - min(zs)) if zs else 0.0

bpy.context.view_layer.update()
h = world_height(base_mesh_objects)
print("[mixamo] 読み込み時の身長: %.4f m（アーマチュアのスケール %s）" % (h, tuple(round(v, 4) for v in base_armature.scale)))
if h > 0.0:
    factor = TARGET_HEIGHT / h
    base_armature.scale = base_armature.scale * factor
    bpy.context.view_layer.update()
    print("[mixamo] 身長を %.2f m に正規化（%.3f 倍）" % (world_height(base_mesh_objects), factor))

# ---- 材質の復元 ----
# Mixamo は材質を 1 つにまとめてしまうので、元の OBJ（材質ごとに分かれている）の
# 一番近い頂点から材質番号を写す。
# Godot 側と同じ見た目になるよう sRGB → リニアに変換して Blender に渡す
def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4
COLORS = {name: tuple(srgb_to_linear(v) for v in rgb) for name, rgb in
          {"Body": (0.07, 0.07, 0.08), "Cloth": (0.83, 0.74, 0.58), "Eye": (1.0, 1.0, 1.0)}.items()}
if os.path.exists(REF_OBJ):
    from mathutils.bvhtree import BVHTree
    before = set(bpy.data.objects)
    bpy.ops.wm.obj_import(filepath=REF_OBJ, forward_axis="NEGATIVE_Z", up_axis="Y")
    ref_objs = [o for o in bpy.data.objects if o not in before and o.type == "MESH"]
    # OBJ は材質やグループごとに複数オブジェクトに分かれて読み込まれることがあるので、全部まとめて扱う
    all_z = [ (o.matrix_world @ v.co).z for o in ref_objs for v in o.data.vertices ]
    ref_h = max(all_z) - min(all_z)
    if ref_h > 0:
        for o in ref_objs:
            o.scale = o.scale * (TARGET_HEIGHT / ref_h)
    bpy.context.view_layer.update()
    # 参照メッシュの「面」に対して最近傍を探す（頂点だと密な部分に引っ張られて帽子が頭の材質になる）
    ref_verts, ref_polys, poly_mat = [], [], []
    for o in ref_objs:
        offset = len(ref_verts)
        ref_verts.extend(o.matrix_world @ v.co for v in o.data.vertices)
        for poly in o.data.polygons:
            ref_polys.append([offset + vi for vi in poly.vertices])
            poly_mat.append(o.data.materials[poly.material_index].name if o.data.materials else "Body")
    bvh = BVHTree.FromPolygons(ref_verts, ref_polys)
    for mesh_obj in base_mesh_objects:
        me = mesh_obj.data
        me.materials.clear()
        mats = {}
        for name, rgb in COLORS.items():
            m = bpy.data.materials.new(name)
            m.use_nodes = True
            m.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*rgb, 1.0)
            m.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.9
            me.materials.append(m)
            mats[name] = len(me.materials) - 1
        counts = {}
        for poly in me.polygons:
            center = mesh_obj.matrix_world @ poly.center
            _, _, idx, _ = bvh.find_nearest(center)
            name = poly_mat[idx] if idx is not None else "Body"
            base = name.split(".")[0]
            poly.material_index = mats.get(base, 0)
            counts[base] = counts.get(base, 0) + 1
        print("[mixamo] 材質を復元: %s" % counts)
        # 確認: 一番高い面（帽子の先）がどの材質になったか
        top = max(me.polygons, key=lambda p: (mesh_obj.matrix_world @ p.center).z)
        tc = mesh_obj.matrix_world @ top.center
        co, _, idx, dist = bvh.find_nearest(tc)
        print("[mixamo] 最上面 %s → 最近傍の面 %s (距離 %.3f) 材質=%s" % (tuple(round(v, 3) for v in tc), tuple(round(v, 3) for v in co), dist, poly_mat[idx]))
    for o in ref_objs:
        bpy.data.objects.remove(o, do_unlink=True)
else:
    print("[mixamo] 参照 OBJ が無いので材質は 1 つのまま: %s" % REF_OBJ)

bpy.ops.object.select_all(action="DESELECT")
for o in [base_armature] + base_mesh_objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = base_armature

os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path, use_selection=True, export_format="GLB", export_yup=True,
    export_animations=True, export_animation_mode="ACTIONS", export_nla_strips=True,
    export_skins=True, export_apply=True,
)
print("[mixamo] 書き出し: %s（アニメ %d 本）" % (out_path, len(actions)))
