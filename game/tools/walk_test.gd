extends Node
## headless で歩行を確認する。前進入力を1秒入れて、移動量と向きを表示して終了する。
##   godot --headless --path game res://tools/walk_test.tscn

func _ready() -> void:
	var world: Node = (load("res://scenes/worlds/gray/gray_world.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(world)
	await get_tree().process_frame
	await get_tree().process_frame
	var player: CharacterBody3D = world.get_node("Player")
	var start := player.global_position
	# 足音がアニメの接地に合わせて出るか（1 秒の歩きで 2 回以上）
	var steps: Array[float] = []
	var rig: Node = player.get_node("Body/TravelerRig")
	if rig.has_signal("footstep"):
		rig.footstep.connect(func(_side: int, strength: float) -> void: steps.append(strength))
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	print("[walk_test] 足音: 1秒で %d 回 強さ=%s" % [steps.size(), str(steps)])
	var steps_ok := steps.size() >= 2 and steps.size() <= 6
	print("[walk_test] 足音の回数: %s" % ("OK" if steps_ok else "NG"))
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
	var top := Vector3(24.0, world_script.get_ground_height(24.0, -14.0) + 1.0, -14.0)
	player.global_position = top
	player.velocity = Vector3.ZERO
	for i in 180:
		await get_tree().physics_frame
	var slid := Vector2(player.global_position.x - top.x, player.global_position.z - top.z).length()
	var gx := player.global_position.x
	var gz := player.global_position.z
	var dx: float = (world_script.get_ground_height(gx + 0.5, gz) - world_script.get_ground_height(gx - 0.5, gz))
	var dz: float = (world_script.get_ground_height(gx, gz + 0.5) - world_script.get_ground_height(gx, gz - 0.5))
	print("[walk_test] 急斜面デバッグ: on_floor=%s floor_angle=%.1f度 地形の傾き=%.1f度 位置=%s" % [
		str(player.is_on_floor()), rad_to_deg(player.get_floor_angle()),
		rad_to_deg(atan(Vector2(dx, dz).length())), str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	print("[walk_test] 急斜面: 3秒後に水平 %.2f m 移動（高さ %.2f → %.2f）" % [slid, top.y, player.global_position.y])
	var slide_ok := slid > 3.0
	print("[walk_test] 急斜面で滑る: %s" % ("OK" if slide_ok else "NG"))

	# 検証エリア: 30度の坂を登って台地に上がれるか
	player.global_position = Vector3(-22.0, 0.5, 5.0)
	player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for i in 600:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var ramp_y := player.global_position.y
	print("[walk_test] 30度の坂: 10秒前進後の高さ %.2f m 位置=%s" % [ramp_y, str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	var ramp_ok := ramp_y > 6.8 and player.global_position.z < -12.0
	print("[walk_test] 30度の坂を登る: %s" % ("OK" if ramp_ok else "NG"))

	# 検証エリア: 崖から落ちる
	player.global_position = Vector3(-15.5, 7.6, -18.0)
	player.velocity = Vector3.ZERO
	Input.action_press("move_right")
	for i in 150:
		await get_tree().physics_frame
	Input.action_release("move_right")
	var cliff_y := player.global_position.y
	print("[walk_test] 崖: 2.5秒後の高さ %.2f m 接地=%s" % [cliff_y, str(player.is_on_floor())])
	var cliff_ok := cliff_y < 1.0 and player.is_on_floor()
	print("[walk_test] 崖から落ちて着地: %s" % ("OK" if cliff_ok else "NG"))

	# 検証エリア: 50度の下り坂を滑り降りる
	player.global_position = Vector3(-22.0, 7.6, -24.0)
	player.velocity = Vector3.ZERO
	Input.action_press("move_forward")
	for i in 60:
		await get_tree().physics_frame
	Input.action_release("move_forward")
	for i in 180:
		await get_tree().physics_frame
	var down_y := player.global_position.y
	print("[walk_test] 50度の下り坂: 4秒後の高さ %.2f m 位置=%s" % [down_y, str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	var down_ok := down_y < 1.0
	print("[walk_test] 50度の下り坂を降りる: %s" % ("OK" if down_ok else "NG"))

	# 段差: 階段（0.25m × 4）を歩いて登る
	var step_ok := await _walk_and_check(player, Vector3(6.0, 0.5, 7.5), "move_back", 240, 0.95, "階段（0.25m 段）を歩いて登る")
	# 段差: 0.45m の段（膝）を歩いて登る
	var knee_ok := await _walk_and_check(player, Vector3(12.0, 0.5, 8.0), "move_back", 180, 0.4, "0.45m の段を足で登る")
	# 段差: 1.5m の段（肩）をよじ登る
	var climb_ok := await _walk_and_check(player, Vector3(22.0, 0.5, 8.0), "move_back", 240, 1.4, "1.5m の段をよじ登る")
	# 段差: 2.2m の段は登れない
	player.global_position = Vector3(27.0, 0.5, 8.0)
	player.velocity = Vector3.ZERO
	Input.action_press("move_back")
	var wall_y := 0.0
	for i in 180:
		await get_tree().physics_frame
		wall_y = maxf(wall_y, player.global_position.y)
	Input.action_release("move_back")
	var wall_ok := wall_y < 0.3
	print("[walk_test] 2.2m の段は登れない: %s（最高 %.2f）" % ["OK" if wall_ok else "NG", wall_y])
	get_tree().quit(0 if (ok and jump_ok and slide_ok and ramp_ok and cliff_ok and down_ok and steps_ok and step_ok and knee_ok and climb_ok and wall_ok) else 1)


func _walk_and_check(player: CharacterBody3D, start: Vector3, action: String, frames: int, min_y: float, label: String) -> bool:
	player.global_position = start
	player.velocity = Vector3.ZERO
	Input.action_press(action)
	var y := 0.0
	for i in frames:
		await get_tree().physics_frame
		y = maxf(y, player.global_position.y)
	Input.action_release(action)
	var passed := y >= min_y
	print("[walk_test] %s: %s（最高 %.2f, 位置 %s）" % [label, "OK" if passed else "NG", y, str(player.global_position.snapped(Vector3(0.1, 0.1, 0.1)))])
	return passed
