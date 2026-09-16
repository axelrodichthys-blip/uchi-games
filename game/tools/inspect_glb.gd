extends SceneTree
## .glb の中身（アニメ・骨・メッシュ・ルートモーションの有無）を表示する。
##   godot --headless --path game --script res://tools/inspect_glb.gd -- res://assets/traveler_mixamo.glb

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path: String = args[0] if args.size() > 0 else "res://assets/traveler_mixamo.glb"
	var packed: PackedScene = load(path)
	if packed == null:
		push_error("読み込めません: " + path)
		quit(1)
		return
	var root: Node = packed.instantiate()
	get_root().add_child(root)
	print("[inspect] ルート: %s (%s)" % [root.name, root.get_class()])
	var mi: MeshInstance3D = _find(root, "MeshInstance3D")
	if mi:
		for si in mi.mesh.get_surface_count():
			var arrays := mi.mesh.surface_get_arrays(si)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var top := -INF
			for v in verts:
				top = maxf(top, v.y)
			var mat := mi.mesh.surface_get_material(si)
			var color := (mat as BaseMaterial3D).albedo_color if mat is BaseMaterial3D else Color(-1, -1, -1)
			print("[inspect] サーフェス %d: 材質=%s 色=%s 頂点=%d 最高点 y=%.3f" % [si, mat.resource_name if mat else "none", str(color), verts.size(), top])
		var aabb := mi.get_aabb()
		print("[inspect] メッシュ %s: AABB 位置=%s 大きさ=%s（ノードのスケール %s）" % [mi.name, str(aabb.position.snapped(Vector3(0.01, 0.01, 0.01))), str(aabb.size.snapped(Vector3(0.01, 0.01, 0.01))), str(mi.global_transform.basis.get_scale())])
	else:
		print("[inspect] メッシュが見つかりません")
	_dump(root, 0)
	var player: AnimationPlayer = _find(root, "AnimationPlayer")
	if player:
		for anim_name in player.get_animation_list():
			var anim := player.get_animation(anim_name)
			var hips_range := _hips_range(anim)
			print("[inspect] アニメ %-24s %.2f 秒  腰の移動 x=%.2f y=%.2f z=%.2f" % [anim_name, anim.length, hips_range.x, hips_range.y, hips_range.z])
	var skel: Skeleton3D = _find(root, "Skeleton3D")
	if skel:
		print("[inspect] 骨 %d 本: %s ..." % [skel.get_bone_count(), ", ".join(PackedStringArray([skel.get_bone_name(0), skel.get_bone_name(1), skel.get_bone_name(2)]))])
		var head := skel.find_bone("mixamorig_Head")
		if head < 0:
			head = skel.find_bone("mixamorig:Head")
		var hips := skel.find_bone("mixamorig_Hips")
		if head >= 0 and hips >= 0:
			print("[inspect] レスト位置: 腰 y=%.3f 頭 y=%.3f（骨格ノードのスケール %s）" % [skel.get_bone_global_rest(hips).origin.y, skel.get_bone_global_rest(head).origin.y, str(skel.global_transform.basis.get_scale())])
	# 歩き・走りクリップの「足が地面を後ろに流れる速さ」= そのクリップが想定している移動速度
	if player and skel:
		for anim_name in ["Walking", "Running", "WalkingBackwards"]:
			if player.has_animation(anim_name):
				var v: float = await _native_speed(player, skel, anim_name)
				print("[inspect] %s の基準速度: %.2f m/s" % [anim_name, v])
	quit(0)


## クリップを固定刻みで進めて左足の前後位置を追い、接地中に地面を流れる速さを返す。
## Mixamo の素のモデルは +Z が正面なので、前進クリップの接地中は足が -Z へ、後退クリップでは +Z へ流れる。
## 接地中の足は体の速さで一定に流れるので、その向きの速さのうち最速域（最大の 8 割以上）の平均を取る。
const MODEL_FACING_Z := 1.0   # 素の glb の正面（+1 で +Z）。traveler_rig.gd 側で 180 度回して使っている

func _native_speed(player: AnimationPlayer, skel: Skeleton3D, anim_name: String) -> float:
	var foot := skel.find_bone("mixamorig_LeftFoot")
	if foot < 0:
		return 0.0
	var anim := player.get_animation(anim_name)
	var dt := 1.0 / 60.0
	var n := int(anim.length / dt)
	# headless ではフレーム間隔が一定でないので、手動更新モードで固定刻みに進めて決定的に測る
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	player.play(anim_name)
	await process_frame   # 初期化を 1 フレーム待つ（手動モードなので勝手には進まない）
	player.seek(0.0, true)
	player.advance(0.0)
	skel.force_update_all_bone_transforms()
	var vs: Array[float] = []
	var prev_z := INF
	for i in n + 1:
		player.advance(dt)
		skel.force_update_all_bone_transforms()
		var p := (skel.global_transform * skel.get_bone_global_pose(foot)).origin
		if prev_z != INF:
			vs.append((p.z - prev_z) / dt)
		prev_z = p.z
	# 接地中に足が流れる向き: 前進なら正面の逆、後退なら正面
	var stance_sign := MODEL_FACING_Z if anim_name.to_lower().contains("backward") else -MODEL_FACING_Z
	var stance: Array[float] = []
	for v in vs:
		if v * stance_sign > 0.05:
			stance.append(v * stance_sign)
	if stance.is_empty():
		return 0.0
	var peak: float = stance.max()
	var plateau: Array[float] = stance.filter(func(v: float) -> bool: return v >= peak * 0.8)
	var total := 0.0
	for v in plateau:
		total += v
	var result := total / plateau.size()
	print("[inspect]   %s 足の前後速度（+Z が正）: %s" % [anim_name, " ".join(vs.map(func(v: float) -> String: return "%.1f" % v))])
	print("[inspect]   %s 接地中（%s 方向）の最速域 %d サンプル → %.2f m/s" % [anim_name, "+Z" if stance_sign > 0 else "-Z", plateau.size(), result])
	return result


func _dump(node: Node, depth: int) -> void:
	if depth <= 3:
		var extra := ""
		if node is MeshInstance3D:
			extra = " mesh=%s surfaces=%d" % [str(node.mesh != null), node.mesh.get_surface_count() if node.mesh else 0]
		if node is Node3D:
			extra += " scale=%s" % str(node.scale)
		print("[inspect] %s%s (%s)%s" % ["  ".repeat(depth), node.name, node.get_class(), extra])
	for child in node.get_children():
		_dump(child, depth + 1)


func _find(node: Node, cls: String) -> Node:
	if node.is_class(cls):
		return node
	for child in node.get_children():
		var found := _find(child, cls)
		if found:
			return found
	return null


## 腰の位置トラックの移動幅（ルートモーションの有無の判定用）
func _hips_range(anim: Animation) -> Vector3:
	for i in anim.get_track_count():
		var track_path := str(anim.track_get_path(i))
		if anim.track_get_type(i) == Animation.TYPE_POSITION_3D and track_path.to_lower().contains("hips"):
			var lo := Vector3(INF, INF, INF)
			var hi := Vector3(-INF, -INF, -INF)
			for k in anim.track_get_key_count(i):
				var p: Vector3 = anim.track_get_key_value(i, k)
				lo = lo.min(p)
				hi = hi.max(p)
			return hi - lo
	return Vector3.ZERO
