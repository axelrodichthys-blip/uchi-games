extends Node
## ワールド固有の仕掛けを headless で確認する。
##   godot --headless --path game res://tools/world_test.tscn
## 今の項目: 灯りに近づくと光が強くなり、次のワールドへ移り始める（雨の景色）

var _target: String = ""


func _ready() -> void:
	var tree := get_tree()
	print("[world_test] 開始")
	var world: Node = (load("res://scenes/worlds/rain/rain_world.tscn") as PackedScene).instantiate()
	tree.root.add_child.call_deferred(world)
	for i in 3:
		await tree.process_frame
	print("[world_test] ワールドを読み込みました")
	var player: CharacterBody3D = world.get_node("Player")
	world.world_changing.connect(_on_world_changing)

	var lights: Array = world.get_node("Props").get_children().filter(func(n: Node) -> bool: return n is OmniLight3D)
	if lights.is_empty():
		print("[world_test] 灯りが見つかりません: NG")
		tree.quit(1)
		return
	var light: OmniLight3D = lights[0]
	var glow_before: float = light.light_energy

	# 灯りの手前に立たせて、灯りへ向かって歩かせる
	var goal: Vector2 = world.lantern_position
	player.global_position = Vector3(goal.x, world.get_ground_height(goal.x, goal.y + 8.0) + 1.0, goal.y + 8.0)
	await tree.physics_frame
	Input.action_press("move_forward")
	for i in 600:
		await tree.physics_frame
		if _target != "":
			break
	Input.action_release("move_forward")
	var ok: bool = _target == world.lantern_next_world
	print("[world_test] 灯りから次のワールドへ: %s（移動先 '%s'）" % ["OK" if ok else "NG", _target])
	var glow_ok: bool = light.light_energy > glow_before + 0.5
	print("[world_test] 近づくと灯りが強くなる: %s（%.2f → %.2f）" % ["OK" if glow_ok else "NG", glow_before, light.light_energy])
	tree.quit(0 if (ok and glow_ok) else 1)


func _on_world_changing(path: String) -> void:
	_target = path
