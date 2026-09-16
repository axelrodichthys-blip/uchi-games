extends Node3D
## アニメクリップを指定時刻で横から描画して PNG に保存する（切れ目を目で探す用）。
##   xvfb-run godot --path game --rendering-driver opengl3 res://tools/clip_view.tscn -- 出力の頭 Jump 0.0,0.2,0.4
## 出力: <頭>_1.png, _2.png ... （カメラは正面をやや斜め前から）

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_base: String = args[0]
	var clip: String = args[1]
	var times: PackedStringArray = args[2].split(",")
	var model: Node3D = (load("res://assets/traveler_mixamo.glb") as PackedScene).instantiate()
	add_child(model)
	model.rotation.y = PI   # Godot の前（-Z）を向かせる
	var player: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-50, 30, 0)
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.75, 0.75, 0.78)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color(0.6, 0.6, 0.65)
	add_child(env)
	var cam := Camera3D.new()
	cam.position = Vector3(2.6, 1.2, -2.2)
	cam.fov = 45
	add_child(cam)
	cam.current = true
	cam.look_at(Vector3(0, 0.9, 0))
	var n := 1
	for t in times:
		player.play(clip)
		player.seek(float(t), true)
		player.pause()
		await get_tree().process_frame
		await get_tree().process_frame
		var img := get_viewport().get_texture().get_image()
		var path := "%s_%d.png" % [out_base, n]
		img.save_png(path)
		print("[clip_view] %s t=%s -> %s" % [clip, t, path])
		n += 1
	get_tree().quit(0)
