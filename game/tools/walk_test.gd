extends Node
## headless で歩行を確認する。前進入力を1秒入れて、移動量と向きを表示して終了する。
##   godot --headless --path game res://tools/walk_test.tscn

func _ready() -> void:
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	var world: Node = (load(main_scene) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: CharacterBody3D = world.get_node("Player")
	var start := player.global_position
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var moved := player.global_position - start
	print("[walk_test] 1秒前進: 移動量=%s 速さ=%.2f m/s 向き(y)=%.1f度" % [
		str(moved.snapped(Vector3(0.01, 0.01, 0.01))),
		Vector2(moved.x, moved.z).length(),
		rad_to_deg(player.get_node("Body").rotation.y)])
	var ok := moved.z < -1.5 and absf(moved.x) < 0.2 and absf(moved.y) < 0.05
	print("[walk_test] 前進: %s" % ("OK" if ok else "NG: 期待した方向・距離ではありません"))

	# ジャンプ: 最高到達点と着地を確認
	var ground_y := player.global_position.y
	Input.action_press("jump")
	await get_tree().physics_frame
	Input.action_release("jump")
	var peak := 0.0
	var landed := false
	for i in 120:
		await get_tree().physics_frame
		peak = maxf(peak, player.global_position.y - ground_y)
		if i > 10 and player.is_on_floor():
			landed = true
			break
	print("[walk_test] ジャンプ: 最高 %.2f m, 着地=%s" % [peak, str(landed)])
	var jump_ok := peak > 0.7 and landed
	print("[walk_test] ジャンプ: %s" % ("OK" if jump_ok else "NG"))

	# 地形: 急斜面の山の上に置くと滑り落ちるか
	var world_script: Node = world
	var top := Vector3(46.0, world_script.get_ground_height(46.0, 0.0) + 1.0, 0.0)
	player.global_position = top
	player.velocity = Vector3.ZERO
	for i in 180:
		await get_tree().physics_frame
	var slid := Vector2(player.global_position.x - top.x, player.global_position.z - top.z).length()
	print("[walk_test] 急斜面: 3秒後に水平 %.2f m 移動（高さ %.2f → %.2f）" % [slid, top.y, player.global_position.y])
	var slide_ok := slid > 3.0
	print("[walk_test] 急斜面で滑る: %s" % ("OK" if slide_ok else "NG"))

	get_tree().quit(0 if (ok and jump_ok and slide_ok) else 1)
