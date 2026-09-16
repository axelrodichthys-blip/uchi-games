extends Node
## ワールド固有の仕掛けを headless で確認する。
##   godot --headless --path game res://tools/world_test.tscn
## 今の項目: 入口（雨の景色の灯り / ネオンのゲート）に近づくと光が強くなり、次のワールドへ移り始める

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
