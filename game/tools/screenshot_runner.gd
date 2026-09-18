extends Node
## メインシーンを読み込んで数フレーム描画し、PNG を保存して終了する。
## 使い方（tools/screenshot.sh から呼ぶ）:
##   godot --path game res://tools/screenshot_runner.tscn -- out.png [frames] [walk|run|jump|hop|idle|walk_away|run_away|fly|fly_up] [count] [every] [world.tscn]
##   jump は右へ歩きながらジャンプ、hop はその場でジャンプ、fly は飛んで右へ進む、fly_up は飛んで上昇。world を省略すると main_scene
##   count > 1 のときは frames 後から every フレームおきに count 枚撮る（out_1.png, out_2.png ...）。
##   動きの指定があるときは横から見えるよう、カメラに対して右へ歩かせる

const DEFAULT_OUT := "screenshot.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else DEFAULT_OUT
	var frames: int = int(args[1]) if args.size() > 1 else 30
	var action: String = args[2] if args.size() > 2 else ""
	var count: int = int(args[3]) if args.size() > 3 else 1
	var every: int = int(args[4]) if args.size() > 4 else 6
	var world_scene: String = args[5] if args.size() > 5 else ""
	# ソフトウェア描画は 1 フレームに時間がかかるので、1 フレーム = 物理 1 ステップに固定して再現性を出す
	Engine.max_physics_steps_per_frame = 1
	var main_scene: String = world_scene if world_scene != "" else ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(main_scene)
	get_tree().root.add_child.call_deferred(packed.instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	# 環境変数で位置と Tuning を上書きできる（例: UCHI_POS="19,0.5,12" UCHI_TUNING="rain_amount=0.1,puddle_amount=0.6"）
	var player_node: Node3D = get_tree().get_first_node_in_group("player")
	if OS.has_environment("UCHI_POS"):
		var p := OS.get_environment("UCHI_POS").split(",")
		if p.size() == 3:
			player_node.global_position = Vector3(float(p[0]), float(p[1]), float(p[2]))
	if OS.has_environment("UCHI_TUNING"):
		for pair in OS.get_environment("UCHI_TUNING").split(","):
			var kv := pair.split("=")
			if kv.size() == 2:
				Tuning.set(kv[0].strip_edges(), float(kv[1]))
	# 動きの確認用: 指定があれば入力を入れ続ける（カメラは横から見る）
	if action != "":
		var rig: Node3D = player_node.get_node("CameraRig")
		# 環境変数で向きも上書きできる（例: UCHI_YAW=-90 UCHI_PITCH=-5。路地の中を覗くときなどに使う）
		rig._pitch = -3.0
		rig._target_distance = 3.0
		if action == "idle":   # 足元の地面を見下ろす（水たまりや影の確認用）
			rig._pitch = -38.0
			rig._target_distance = 2.6
		if OS.has_environment("UCHI_YAW"):
			rig._yaw = float(OS.get_environment("UCHI_YAW"))
		if OS.has_environment("UCHI_PITCH"):
			rig._pitch = float(OS.get_environment("UCHI_PITCH"))
		rig._apply_rotation()
		if action == "walk":
			Input.action_press("move_right")
		elif action == "run":
			Input.action_press("move_right")
			Input.action_press("run")
		elif action == "jump":
			Input.action_press("move_right")
		elif action == "walk_away":
			Input.action_press("move_forward")
		elif action == "run_away":
			Input.action_press("move_forward")
			Input.action_press("run")
	var flying := action == "fly" or action == "fly_up"
	for i in frames:
		if (action == "jump" or action == "hop") and i == frames - 14:
			Input.action_press("jump")
		if flying:
			# F で飛び立って、しばらく上昇 → そのあと前へ進む
			if i == 2:
				Input.action_press("fly")
			elif i == 4:
				Input.action_release("fly")
				Input.action_press("jump")
			elif i == int(frames * 0.5):
				Input.action_release("jump")
				if action == "fly":
					Input.action_press("move_right")
		await get_tree().process_frame
	var err := _save(out_path if count <= 1 else _numbered(out_path, 1))
	for n in range(2, count + 1):
		for i in every:
			await get_tree().process_frame
		err = _save(_numbered(out_path, n))
	get_tree().quit(0 if err == OK else 1)


func _numbered(path: String, n: int) -> String:
	return "%s_%d.%s" % [path.get_basename(), n, path.get_extension()]


func _save(path: String) -> int:
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(path)
	if err == OK:
		print("[screenshot] 保存しました: %s (%dx%d)" % [path, image.get_width(), image.get_height()])
	else:
		push_error("[screenshot] 保存に失敗: %s (err=%d)" % [path, err])
	return err
