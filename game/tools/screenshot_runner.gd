extends Node
## メインシーンを読み込んで数フレーム描画し、PNG を保存して終了する。
## 使い方（tools/screenshot.sh から呼ぶ）:
##   godot --path game res://tools/screenshot_runner.tscn -- out.png [frames] [walk|run|jump|hop|idle] [count] [every]
##   jump は右へ歩きながらジャンプ、hop はその場でジャンプ
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
	# ソフトウェア描画は 1 フレームに時間がかかるので、1 フレーム = 物理 1 ステップに固定して再現性を出す
	Engine.max_physics_steps_per_frame = 1
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(main_scene)
	get_tree().root.add_child.call_deferred(packed.instantiate())
	await get_tree().process_frame
	await get_tree().process_frame
	# 動きの確認用: 指定があれば入力を入れ続ける（カメラは横から見る）
	if action != "":
		var rig: Node3D = get_tree().root.get_node("GrayWorld/Player/CameraRig")
		rig._pitch = -3.0
		rig._target_distance = 3.0
		rig._apply_rotation()
		if action == "walk":
			Input.action_press("move_right")
		elif action == "run":
			Input.action_press("move_right")
			Input.action_press("run")
		elif action == "jump":
			Input.action_press("move_right")
	for i in frames:
		if (action == "jump" or action == "hop") and i == frames - 14:
			Input.action_press("jump")
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
