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
	print("[walk_test] %s" % ("OK" if ok else "NG: 期待した方向・距離ではありません"))
	get_tree().quit(0 if ok else 1)
