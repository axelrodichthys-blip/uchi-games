extends Node
## スマホ用タッチ操作を headless で確認する。画面のタッチを作って送り、動きが出るかを見る。
##   godot --headless --path game res://tools/touch_test.tscn

var _ok := true


func _ready() -> void:
	var tree := get_tree()
	Tuning.touch_controls = 1   # 常に表示（PC でも出す）
	var world: Node = (load("res://scenes/worlds/gray/gray_world.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(world)
	for i in 3:
		await tree.process_frame
	var player: CharacterBody3D = world.get_node("Player")
	var ui: Control = world.get_node("TouchControls/TouchUI")
	var rig: Node3D = player.get_node("CameraRig")
	# headless の画面は 64x64 と極小なので、スマホくらいの大きさに固定して試す
	ui.set_anchors_preset(Control.PRESET_TOP_LEFT)
	ui.size = Vector2(1280, 720)
	await tree.process_frame
	var w := ui.size.x
	var h := ui.size.y
	print("[touch_test] 画面 %.0f x %.0f, タッチ操作の表示=%s" % [w, h, str(ui.visible)])
	_check(ui.visible, "タッチ操作が表示される")

	# 1. 左側のスティックを上へ倒す → 前に進む
	player.global_position = Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	var stick := Vector2(w * 0.2, h * 0.8)
	_touch(0, stick, true)
	await tree.physics_frame
	_drag(0, stick, stick + Vector2(0, -120))
	var start := player.global_position
	for i in 90:
		await tree.physics_frame
	var moved := start.distance_to(player.global_position)
	_touch(0, stick + Vector2(0, -120), false)
	print("[touch_test] スティックで移動: %.2f m" % moved)
	_check(moved > 2.0, "スティックで前に進む")

	# 止まるか
	for i in 30:
		await tree.physics_frame
	var stopped := Vector2(player.velocity.x, player.velocity.z).length()
	print("[touch_test] 指を離したあとの速さ: %.2f m/s" % stopped)
	_check(stopped < 0.2, "指を離すと止まる")

	# 2. 右側をなぞる → 視点が回る
	var yaw_before: float = rig.get_yaw()
	var look := Vector2(w * 0.75, h * 0.5)
	_touch(1, look, true)
	await tree.process_frame
	_drag(1, look, look + Vector2(200, 0))
	await tree.process_frame
	_touch(1, look + Vector2(200, 0), false)
	var yaw_after: float = rig.get_yaw()
	print("[touch_test] 視点の回転: %.1f 度" % rad_to_deg(yaw_after - yaw_before))
	_check(absf(yaw_after - yaw_before) > 0.1, "右側のドラッグで視点が回る")

	# 3. ジャンプボタン
	player.global_position = Vector3(0, 1.0, 0)
	player.velocity = Vector3.ZERO
	for i in 20:
		await tree.physics_frame
	var ground := player.global_position.y
	var jump_pos := _button_center(ui, "jump")
	_touch(2, jump_pos, true)
	for i in 5:
		await tree.physics_frame
	_touch(2, jump_pos, false)
	var peak := 0.0
	for i in 90:
		await tree.physics_frame
		peak = maxf(peak, player.global_position.y - ground)
	print("[touch_test] ジャンプの高さ: %.2f m" % peak)
	_check(peak > 0.7, "ジャンプボタンで跳ぶ")

	# 4. 走るボタン: タップで入り、もう一度タップで切れる
	var run_pos := _button_center(ui, "run")
	_touch(3, run_pos, true)
	await tree.physics_frame
	_touch(3, run_pos, false)
	await tree.physics_frame
	var run_on := Input.is_action_pressed("run")
	_touch(3, run_pos, true)
	await tree.physics_frame
	_touch(3, run_pos, false)
	await tree.physics_frame
	var run_off := not Input.is_action_pressed("run")
	_check(run_on and run_off, "走るボタンがタップで入り切りできる")

	# 5. 2 本指でつまむとカメラの距離が変わる
	var dist_before: float = rig._target_distance
	var a := Vector2(w * 0.65, h * 0.5)
	var b := Vector2(w * 0.85, h * 0.5)
	_touch(4, a, true)
	_touch(5, b, true)
	await tree.process_frame
	_drag(4, a, a)
	_drag(5, b, b)
	await tree.process_frame
	for i in 6:
		_drag(4, a, a + Vector2(-20.0 * i, 0))
		_drag(5, b, b + Vector2(20.0 * i, 0))
		await tree.process_frame
	_touch(4, a, false)
	_touch(5, b, false)
	var dist_after: float = rig._target_distance
	print("[touch_test] つまんだあとのカメラ距離: %.2f → %.2f" % [dist_before, dist_after])
	_check(absf(dist_after - dist_before) > 0.2, "2 本指でカメラの距離が変わる")

	tree.quit(0 if _ok else 1)


## ボタンの位置は画面の大きさから計算されるので、UI 自身に聞く
func _button_center(ui: Control, id: String) -> Vector2:
	for b in ui._buttons():
		if b["id"] == id:
			return b["center"] if b["shape"] == "circle" else (b["rect"] as Rect2).get_center()
	return Vector2.ZERO


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = pos
	e.pressed = pressed
	Input.parse_input_event(e)


func _drag(index: int, from: Vector2, to: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = to
	e.relative = to - from
	Input.parse_input_event(e)


func _check(passed: bool, label: String) -> void:
	print("[touch_test] %s: %s" % [label, "OK" if passed else "NG"])
	if not passed:
		_ok = false
