# Mixamo からダウンロードした FBX（複数）を 1 つの .glb にまとめる。
#
# 使い方（ヘッドレス）:
#   blender --background --python tools/blender/mixamo_fbx_to_glb.py -- <FBXのフォルダ> <出力.glb>
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
        base_mesh_objects = meshes
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

# Mixamo の FBX は cm 単位（100 倍）で来ることが多いので、1/100 にする
for o in [base_armature] + base_mesh_objects:
    if max(o.scale) > 10.0:
        o.scale = o.scale / 100.0
bpy.ops.object.select_all(action="DESELECT")
for o in [base_armature] + base_mesh_objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = base_armature
bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)

os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
bpy.ops.export_scene.gltf(
    filepath=out_path, use_selection=True, export_format="GLB", export_yup=True,
    export_animations=True, export_animation_mode="ACTIONS", export_nla_strips=True,
    export_skins=True, export_apply=True,
)
print("[mixamo] 書き出し: %s（アニメ %d 本）" % (out_path, len(actions)))
