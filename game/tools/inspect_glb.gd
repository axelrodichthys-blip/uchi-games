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


## クリップを少しずつ進めて左足の前後位置を追い、接地中（後ろへ流れる）の速さの中央値を返す
func _native_speed(player: AnimationPlayer, skel: Skeleton3D, anim_name: String) -> float:
	var foot := skel.find_bone("mixamorig_LeftFoot")
	if foot < 0:
		return 0.0
	var anim := player.get_animation(anim_name)
	var n := int(anim.length * 60.0)
	var zs: Array[float] = []
	var ys: Array[float] = []
	var dts: Array[float] = []
	player.play(anim_name)
	await process_frame
	for i in n + 1:
		await process_frame
		var p := (skel.global_transform * skel.get_bone_global_pose(foot)).origin
		zs.append(p.z)
		ys.append(p.y)
		dts.append(get_root().get_process_delta_time())
	var dt: float = dts[dts.size() / 2]
	print("[inspect]   %s 左足 z: %.3f 〜 %.3f, y: %.3f 〜 %.3f, フレーム間隔 %.4f 秒, 骨格スケール %s" % [anim_name, zs.min(), zs.max(), ys.min(), ys.max(), dt, str(skel.global_transform.basis.get_scale())])
	var back_speeds: Array[float] = []
	for i in n:
		var v := (zs[i + 1] - zs[i]) / dt   # +Z = 後ろ
		if v > 0.05:
			back_speeds.append(v)
	back_speeds.sort()
	if back_speeds.is_empty():
		return 0.0
	var pct := func(q: float) -> float: return back_speeds[int(clampf(q, 0.0, 0.999) * back_speeds.size())]
	print("[inspect]   接地中の後ろ向き速度の分布: 25%%=%.2f 50%%=%.2f 75%%=%.2f 90%%=%.2f" % [pct.call(0.25), pct.call(0.5), pct.call(0.75), pct.call(0.9)])
	return pct.call(0.75)


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
