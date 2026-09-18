extends Node3D
## .glb を四面（正面 / 左 / 背面 / 右）から描いて PNG に保存する。ターンアラウンドの見比べ用。
##   xvfb-run godot --path game --rendering-driver opengl3 res://tools/model_view.tscn -- 出力の頭 res://assets/x.glb [高さ]
## 出力: <頭>_1.png（正面）, _2.png（左）, _3.png（背面）, _4.png（右）

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_base: String = args[0]
	var model_path: String = args[1]
	var height: float = float(args[2]) if args.size() > 2 else 1.6
	var scene := load(model_path) as PackedScene
	if scene == null:
		push_error("読めない: %s" % model_path)
		get_tree().quit(1)
		return
	var model: Node3D = scene.instantiate()
	add_child(model)
	model.rotation.y = PI   # Blender からの .glb は +Z が前。Godot の前（-Z）に向ける

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-38, 28, 0)
	key.light_energy = 1.15
	add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -140, 0)
	fill.light_energy = 0.35
	add_child(fill)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.93, 0.93, 0.92)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.72, 0.72, 0.74)
	env.environment.ambient_light_energy = 1.0
	add_child(env)

	var cam := Camera3D.new()
	cam.fov = 28.0
	add_child(cam)
	cam.current = true
	var look := Vector3(0, height * 0.5, 0)
	var dist := height * 2.6
	# Godot の前は -Z。正面から見るにはカメラを -Z 側に置く
	var angles := [0.0, 90.0, 180.0, 270.0]
	var names := ["正面", "左側面", "背面", "右側面"]
	for i in angles.size():
		var a: float = deg_to_rad(float(angles[i]))
		cam.position = look + Vector3(sin(a) * dist, height * 0.06, -cos(a) * dist)
		cam.look_at(look)
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "%s_%d.png" % [out_base, i + 1]
		img.save_png(path)
		print("[model_view] %s -> %s" % [names[i], path])
	get_tree().quit(0)
