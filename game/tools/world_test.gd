extends Node
## ワールド固有の仕掛けを headless で確認する。
##   godot --headless --path game res://tools/world_test.tscn
## 今の項目:
##   - 入口（雨の景色の灯り / ネオンのゲート）に近づくと光が強くなり、次のワールドへ移り始める
##   - 雨の景色の小屋・柵・街灯が飛び石の道を塞がず、雨どいの水が雨と一緒に止まる
##   - ネオンの路地に入って奥の自販機まで歩けて、行き止まりの壁より外へは出られない
##   - ネオンの通行人の影が動き、湯気が出ていて、どちらも F1 の設定で消せる
##   - 低画質（スマホ）でも全ワールドが組み立てられる

const CASES := [
	{
		"scene": "res://scenes/worlds/rain/rain_world.tscn",
		"name": "雨の景色の灯り",
		"point": "lantern_position",
		"next": "lantern_next_world",
	},
	{
		"scene": "res://scenes/worlds/neon/neon_world.tscn",
		"name": "ネオンのゲート",
		"point": "gate_position",
		"next": "gate_next_world",
	},
]

var _target: String = ""
var _ok := true


func _ready() -> void:
	for c in CASES:
		await _run_case(c)
	await _run_rain_extras()
	await _run_neon_extras()
	await _run_low_quality()
	get_tree().quit(0 if _ok else 1)


func _run_case(c: Dictionary) -> void:
	var tree := get_tree()
	_target = ""
	var world: Node = (load(c["scene"]) as PackedScene).instantiate()
	tree.root.add_child.call_deferred(world)
	for i in 3:
		await tree.process_frame
	var player: CharacterBody3D = world.get_node("Player")
	world.world_changing.connect(_on_world_changing)

	var lights: Array = world.get_node("Props").get_children().filter(func(n: Node) -> bool: return n is OmniLight3D)
	if lights.is_empty():
		_fail("%s: 光源が見つかりません" % c["name"])
		world.queue_free()
		return
	# 入口の光（入口にいちばん近い光源）を選ぶ
	var goal: Vector2 = world.get(c["point"])
	var target_point := Vector3(goal.x, 0.0, goal.y)
	var light: OmniLight3D = lights[0]
	for l in lights:
		if Vector2(l.global_position.x - goal.x, l.global_position.z - goal.y).length() < Vector2(light.global_position.x - goal.x, light.global_position.z - goal.y).length():
			light = l
	var glow_before: float = light.light_energy

	# 入口の手前に立たせて、入口へ向かって歩かせる
	player.global_position = Vector3(goal.x, world.get_ground_height(goal.x, goal.y + 9.0) + 1.0, goal.y + 9.0)
	await tree.physics_frame
	Input.action_press("move_forward")
	for i in 600:
		await tree.physics_frame
		if _target != "":
			break
	Input.action_release("move_forward")

	var expected: String = world.get(c["next"])
	_check(_target == expected, "%s から次のワールドへ（%s）" % [c["name"], _target])
	_check(light.light_energy > glow_before + 0.5, "%s が近づくと強くなる（%.2f → %.2f）" % [c["name"], glow_before, light.light_energy])
	world.queue_free()
	await tree.process_frame


func _on_world_changing(path: String) -> void:
	_target = path


func _check(passed: bool, label: String) -> void:
	print("[world_test] %s: %s" % [label, "OK" if passed else "NG"])
	if not passed:
		_ok = false


func _fail(label: String) -> void:
	_check(false, label)


# ---------------------------------------------------------------- ネオンの街の中身
## 路地・通行人・湯気を確認する。どれも「歩いていて気づくもの」なので、
## 見た目はスクリーンショットで、動きと当たり判定はここで確かめる
func _run_neon_extras() -> void:
	var tree := get_tree()
	var world: Node = (load("res://scenes/worlds/neon/neon_world.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(world)
	for i in 3:
		await tree.process_frame
	var player: CharacterBody3D = world.get_node("Player")
	var consts: Dictionary = world.get_script().get_script_constant_map()
	var street_half: float = consts["STREET_HALF"]
	var alley_length: float = consts["ALLEY_LENGTH"]
	var alley: Dictionary = consts["ALLEYS"][2]
	var side: float = alley["side"]
	var az: float = alley["z"]

	# 路地の入口に立ち、路地の奥（x が増える向き）へ歩く
	var rig: Node3D = player.get_node("CameraRig")
	rig._yaw = -90.0 * side
	rig._apply_rotation()
	var start_x: float = side * (street_half - 1.0)
	player.global_position = Vector3(start_x, world.get_ground_height(start_x, az) + 1.0, az)
	player.velocity = Vector3.ZERO
	await tree.physics_frame
	Input.action_press("move_forward")
	for i in 900:
		await tree.physics_frame
	Input.action_release("move_forward")
	var reached: float = player.global_position.x * side
	var drift: float = absf(player.global_position.z - az)
	_check(reached > street_half + alley_length - 7.0 and drift < 4.0,
		"路地の奥まで歩いて行ける（奥行き %.1f m, 横ずれ %.1f m）" % [reached, drift])
	_check(reached < street_half + alley_length + 5.0,
		"路地の行き止まりで止まる（奥行き %.1f m）" % reached)

	# 通行人の影が歩いているか
	var walkers: Array = world._walkers
	var before: Array[Vector3] = []
	for w in walkers:
		before.append((w["node"] as Node3D).global_position)
	for i in 60:
		await tree.process_frame
	var moved := 0
	for i in walkers.size():
		var node: Node3D = walkers[i]["node"]
		if node.visible and node.global_position.distance_to(before[i]) > 0.1:
			moved += 1
	_check(moved >= 3, "通行人の影が歩いている（%d 人が動いた / 全 %d 人）" % [moved, walkers.size()])

	# 湯気が出ているか
	var steam: Array = world._steam
	var emitting := steam.filter(func(p: GPUParticles3D) -> bool: return p.emitting)
	_check(emitting.size() == steam.size() and steam.size() >= 3,
		"湯気が出ている（%d / %d か所）" % [emitting.size(), steam.size()])

	# F1 で湯気と通行人を消せるか
	var steam_was: float = Tuning.steam_amount
	var crowd_was: float = Tuning.crowd_amount
	Tuning.steam_amount = 0.0
	Tuning.crowd_amount = 0.0
	for i in 3:
		await tree.process_frame
	var still_on := steam.filter(func(p: GPUParticles3D) -> bool: return p.emitting)
	var still_shown := walkers.filter(func(w: Dictionary) -> bool: return (w["node"] as Node3D).visible)
	_check(still_on.is_empty() and still_shown.is_empty(),
		"F1 で湯気と通行人を消せる（湯気 %d か所 / 通行人 %d 人 が残った）" % [still_on.size(), still_shown.size()])
	Tuning.steam_amount = steam_was
	Tuning.crowd_amount = crowd_was

	world.queue_free()
	await tree.process_frame


## 低画質（スマホの自動設定と同じ）で全ワールドを組み立てられるか。
## 軽量化の分岐は光源や粒の数を減らすので、そこで壊れていないかを見る
func _run_low_quality() -> void:
	var tree := get_tree()
	var was: int = Tuning.graphics_quality
	Tuning.graphics_quality = 2   # 低
	for path in ["res://scenes/worlds/rain/rain_world.tscn",
			"res://scenes/worlds/neon/neon_world.tscn",
			"res://scenes/worlds/gray/gray_world.tscn"]:
		var world: Node = (load(path) as PackedScene).instantiate()
		tree.root.add_child.call_deferred(world)
		for i in 5:
			await tree.process_frame
		var player: Node3D = world.get_node("Player")
		_check(is_instance_valid(player) and player.global_position.y > -20.0,
			"低画質で %s を組み立てられる" % path.get_file())
		world.queue_free()
		await tree.process_frame
	Tuning.graphics_quality = was


# ---------------------------------------------------------------- 雨の景色の小物
## 小屋・柵・街灯は「道沿いに置く」ので、飛び石の道を歩けなくしていないかを確かめる。
## 雨どいの水は F1 で雨を止めたら一緒に止まること
func _run_rain_extras() -> void:
	var tree := get_tree()
	var world: Node = (load("res://scenes/worlds/rain/rain_world.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(world)
	for i in 3:
		await tree.process_frame
	var player: CharacterBody3D = world.get_node("Player")

	# 飛び石の道をたどって灯りの近くまで行けるか。まっすぐではなく、
	# 石が並んでいる曲線（rain_world の wobble と同じ式）を追いかける
	var start := Vector2(0.0, -4.0)
	var goal: Vector2 = world.lantern_position
	var dir := (goal - start).normalized()
	var side := Vector2(-dir.y, dir.x)
	var total := start.distance_to(goal)
	var path_at := func(d: float) -> Vector2:
		return start + dir * d + side * (sin(d * 0.12) * 2.5)
	player.global_position = Vector3(start.x, world.get_ground_height(start.x, start.y) + 1.0, start.y)
	player.velocity = Vector3.ZERO
	var rig: Node3D = player.get_node("CameraRig")
	await tree.physics_frame
	Input.action_press("move_forward")
	Input.action_press("run")   # 136m あるので走る
	var nearest := 9999.0
	var travelled := 0.0
	for i in 2400:
		var here := Vector2(player.global_position.x, player.global_position.z)
		travelled = clampf((here - start).dot(dir), 0.0, total)
		var aim: Vector2 = path_at.call(minf(travelled + 6.0, total))
		var to_aim := aim - here
		# カメラの前方は -Z を yaw で回した向き = (-sin, -cos)。その逆算
		rig._yaw = rad_to_deg(atan2(-to_aim.x, -to_aim.y))
		rig._apply_rotation()
		await tree.physics_frame
		nearest = minf(nearest, here.distance_to(goal))
		if nearest < 8.0:
			break
	Input.action_release("move_forward")
	Input.action_release("run")
	_check(nearest < 8.0, "小物が飛び石の道を塞いでいない（灯りまで残り %.1f m）" % nearest)

	# 雨どいの水
	var gutters: Array = world._gutters
	_check(gutters.size() >= 1 and gutters.all(func(g: GPUParticles3D) -> bool: return g.emitting),
		"雨どいから水が落ちている（%d か所）" % gutters.size())
	var was: float = Tuning.rain_amount
	Tuning.rain_amount = 0.0
	for i in 3:
		await tree.process_frame
	_check(gutters.all(func(g: GPUParticles3D) -> bool: return not g.emitting),
		"雨を止めると雨どいの水も止まる")
	Tuning.rain_amount = was

	world.queue_free()
	await tree.process_frame
