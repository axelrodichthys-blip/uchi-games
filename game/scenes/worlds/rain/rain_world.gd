extends WorldBase
## 最初のワールド「雨の景色」。灰色の空、濡れた地面と水たまりの反射、雨粒、雨音。
## 見つけるもの: 遠く（-Z 方向、約 140m）にぼんやり灯る灯り。飛び石の道がそこへ続く。
## 地形の共通部分は world_base.gd。ここではワールド固有の小物と、雨をプレイヤーに追従させる。

@export_group("雨")
@export var rain_height: float = 9.0        # プレイヤーの頭上どこから降らせるか

@export_group("見つけるもの")
@export var lantern_position: Vector2 = Vector2(6.0, -140.0)

@onready var props: Node3D = $Props
@onready var rain: CPUParticles3D = $Rain
@onready var rain_sound: AudioStreamPlayer = $RainSound

var _rock_mat: StandardMaterial3D
var _post_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D


func _ready() -> void:
	super()
	_setup_rain_sound()


func _process(delta: float) -> void:
	super(delta)
	# 雨はプレイヤーの周りだけに降らせる（遠くは見えないので無駄にしない）
	rain.global_position = player.global_position + Vector3(0.0, rain_height, 0.0)
	rain_sound.volume_db = Tuning.ambient_volume_db


func _decorate() -> void:
	_rock_mat = WorldBase.flat_material(Color(0.17, 0.18, 0.20), 0.6)
	_post_mat = WorldBase.flat_material(Color(0.12, 0.12, 0.13), 0.7)
	_stone_mat = WorldBase.flat_material(Color(0.30, 0.31, 0.34), 0.35)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 100

	# 岩: 低く潰した粗い球
	for i in 70:
		var x := rng.randf_range(-150.0, 150.0)
		var z := rng.randf_range(-170.0, 130.0)
		if Vector2(x, z).length() < 8.0:
			continue
		var r := rng.randf_range(0.5, 2.2)
		var mesh := SphereMesh.new()
		mesh.radius = r
		mesh.height = r * rng.randf_range(0.9, 1.4)
		mesh.radial_segments = 7
		mesh.rings = 4
		var shape := SphereShape3D.new()
		shape.radius = r * 0.8
		add_static_mesh(props, Vector3(x, get_ground_height(x, z) - r * 0.25, z), mesh, shape,
			Vector3(rng.randf_range(-0.2, 0.2), rng.randf_range(0.0, TAU), rng.randf_range(-0.2, 0.2)), _rock_mat)

	# 立ち枯れの杭のような細い柱（風景の奥行き用）
	for i in 36:
		var x := rng.randf_range(-160.0, 160.0)
		var z := rng.randf_range(-180.0, 120.0)
		if Vector2(x, z).length() < 10.0:
			continue
		var h := rng.randf_range(2.5, 7.0)
		add_static_box(props, Vector3(x, get_ground_height(x, z) + h * 0.5 - 0.3, z), Vector3(0.28, h, 0.28),
			Vector3(rng.randf_range(-0.08, 0.08), rng.randf_range(0.0, TAU), rng.randf_range(-0.08, 0.08)), _post_mat)

	_build_path_and_lantern(rng)


## 出現地点から灯りまで飛び石を並べ、先に灯りを置く
func _build_path_and_lantern(rng: RandomNumberGenerator) -> void:
	var start := Vector2(0.0, -4.0)
	var goal := lantern_position
	var dir := (goal - start).normalized()
	var side := Vector2(-dir.y, dir.x)
	var dist := start.distance_to(goal)
	var d := 0.0
	while d < dist - 4.0:
		var wobble := sin(d * 0.12) * 2.5 + rng.randf_range(-0.4, 0.4)
		var p := start + dir * d + side * wobble
		var y := get_ground_height(p.x, p.y)
		var size := Vector3(rng.randf_range(0.9, 1.4), 0.12, rng.randf_range(0.7, 1.0))
		add_static_box(props, Vector3(p.x, y + 0.02, p.y), size, Vector3(0, rng.randf_range(-0.4, 0.4), 0), _stone_mat, 4)
		d += rng.randf_range(2.0, 2.8)

	# 灯り: 柱 + 発光する球 + フォグに消えない光の暈（遠くからでも見える目印）
	var gx := goal.x
	var gz := goal.y
	var gy := get_ground_height(gx, gz)
	add_static_box(props, Vector3(gx, gy + 1.6, gz), Vector3(0.35, 3.4, 0.35), Vector3.ZERO, _post_mat, 1)
	var lamp := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.32
	sphere.height = 0.64
	sphere.radial_segments = 10
	sphere.rings = 5
	lamp.mesh = sphere
	var lamp_mat := StandardMaterial3D.new()
	lamp_mat.albedo_color = Color(1.0, 0.82, 0.55)
	lamp_mat.emission_enabled = true
	lamp_mat.emission = Color(1.0, 0.72, 0.40)
	lamp_mat.emission_energy_multiplier = 2.5
	lamp_mat.disable_fog = true
	lamp.material_override = lamp_mat
	lamp.position = Vector3(gx, gy + 3.5, gz)
	props.add_child(lamp)
	var halo := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(9.0, 9.0)
	halo.mesh = quad
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.disable_fog = true
	halo_mat.no_depth_test = false
	var grad := Gradient.new()
	grad.set_color(0, Color(1.0, 0.70, 0.38, 0.55))
	grad.set_color(1, Color(1.0, 0.70, 0.38, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 64
	tex.height = 64
	halo_mat.albedo_texture = tex
	halo.material_override = halo_mat
	halo.position = lamp.position
	props.add_child(halo)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.5)
	light.light_energy = 2.0
	light.omni_range = 14.0
	light.position = lamp.position
	props.add_child(light)


func _setup_rain_sound() -> void:
	var stream := rain_sound.stream
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	rain_sound.volume_db = Tuning.ambient_volume_db
	rain_sound.play()
