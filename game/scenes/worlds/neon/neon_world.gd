extends WorldBase
## 2 つ目のワールド「ネオン」。暗闇に光る看板、濡れた路面の映り込み、電子音。
## 見つけるもの: 道の突き当たり（-Z 方向、約 150m）に光るゲート。くぐると「雨の景色」へ戻る。
## 地形の共通部分は world_base.gd。ここでは道に沿ったビルと看板、ゲート、環境音を組み立てる。
##
## 色（3〜5 色で統一する）:
##   闇 #07080F / ビル #12141F / ピンク #FF3D80 / シアン #2BE6FF / 黄 #FFD447

const STREET_HALF := 9.0        # 道の半分の幅 m
const BLOCK := 13.0             # ビル（看板）の間隔 m。シェーダーの sign_spacing と合わせる
const NEON_COLORS := [Color(1.00, 0.24, 0.50), Color(0.17, 0.90, 1.00), Color(1.00, 0.83, 0.28)]

@export_group("街")
@export var street_length: float = 170.0   # 道の長さ（±この値まで建てる）m
@export var street_lights: int = 8         # 道に落とす光の数（内蔵 GPU のため増やしすぎない）

@export_group("見つけるもの")
@export var gate_position: Vector2 = Vector2(0.0, -150.0)
@export var gate_glow_radius: float = 18.0
@export var gate_enter_radius: float = 3.5
@export var gate_next_world: String = "res://scenes/worlds/rain/rain_world.tscn"

@onready var props: Node3D = $Props
@onready var hum: AudioStreamPlayer = $Hum

var _building_mat: StandardMaterial3D
var _frame_mat: StandardMaterial3D


## 道は平ら。歩道だけ少し高く、遠くはゆるやかに起伏させる
func _terrain_height(x: float, z: float) -> float:
	var away := smoothstep(STREET_HALF + 14.0, STREET_HALF + 60.0, absf(x))
	return _noise.get_noise_2d(x, z) * hill_height * away


func _ready() -> void:
	super()
	_setup_hum()


func _process(delta: float) -> void:
	super(delta)
	hum.volume_db = Tuning.ambient_volume_db
	var mat := terrain_mesh.material_override as ShaderMaterial
	if mat and not is_equal_approx(float(mat.get_shader_parameter("puddle_amount")), Tuning.puddle_amount):
		mat.set_shader_parameter("puddle_amount", Tuning.puddle_amount)


func _decorate() -> void:
	_building_mat = WorldBase.flat_material(Color(0.07, 0.08, 0.12), 0.85)
	_frame_mat = WorldBase.flat_material(Color(0.04, 0.045, 0.06), 0.7)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 7
	_build_street(rng)
	_build_gate()


## 道の両側にビルを建て、道に面した壁に光る看板を付ける
func _build_street(rng: RandomNumberGenerator) -> void:
	var z := -street_length
	var light_every := maxi(int((street_length * 2.0 / BLOCK) / maxf(street_lights, 1.0)), 1)
	var index := 0
	while z < street_length:
		var depth := rng.randf_range(10.0, 18.0)
		for side in [-1.0, 1.0]:
			var width := rng.randf_range(BLOCK * 0.65, BLOCK * 0.95)
			var height := rng.randf_range(10.0, 34.0)
			var x: float = side * (STREET_HALF + 1.0 + depth * 0.5)
			var center := Vector3(x, height * 0.5, z + BLOCK * 0.5)
			add_static_box(props, center, Vector3(depth, height, width), Vector3.ZERO, _building_mat, 1)
			# 屋上の縁（暗い帯）で輪郭を出す
			add_static_box(props, center + Vector3(0, height * 0.5 + 0.3, 0), Vector3(depth + 0.6, 0.6, width + 0.6), Vector3.ZERO, _frame_mat, 1)
			_add_signs(rng, side, x, height, z + BLOCK * 0.5, width, depth, index % light_every == 0)
		z += BLOCK
		index += 1


## ビル 1 棟ぶんの看板。縦長・横長をいくつか。光源は数を絞って置く
func _add_signs(rng: RandomNumberGenerator, side: float, x: float, height: float, z: float, width: float, depth: float, with_light: bool) -> void:
	var face_x: float = x - side * (depth * 0.5 + 0.08)   # 道に面した壁の少し手前
	var count := rng.randi_range(1, 3)
	var brightest := Color.BLACK
	var brightest_y := 0.0
	for i in count:
		var color: Color = NEON_COLORS[rng.randi_range(0, NEON_COLORS.size() - 1)]
		var vertical := rng.randf() < 0.55
		var y := rng.randf_range(3.0, maxf(height - 3.0, 4.0))
		var sign_size: Vector3
		if vertical:
			sign_size = Vector3(0.3, rng.randf_range(3.5, 8.0), rng.randf_range(0.7, 1.4))
		else:
			sign_size = Vector3(0.3, rng.randf_range(0.8, 1.6), rng.randf_range(2.5, minf(width - 1.0, 6.0)))
		var pos := Vector3(face_x, y, z + rng.randf_range(-width * 0.3, width * 0.3))
		_add_sign_box(pos, sign_size, color)
		if y > brightest_y:
			brightest_y = y
			brightest = color
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = brightest
		light.light_energy = 4.5
		light.omni_range = 30.0
		light.omni_attenuation = 1.2
		light.position = Vector3(face_x - side * 3.5, clampf(brightest_y, 3.0, 10.0), z)
		props.add_child(light)


func _add_sign_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = _emissive_material(color, 2.2)
	mi.position = pos
	props.add_child(mi)


static func _emissive_material(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	m.disable_fog = false
	return m


## 道の突き当たりのゲート（別のワールドへの入口）
func _build_gate() -> void:
	var gx := gate_position.x
	var gz := gate_position.y
	var gy := get_ground_height(gx, gz)
	var pillar := Vector3(1.2, 9.0, 1.2)
	for side in [-1.0, 1.0]:
		add_static_box(props, Vector3(gx + side * 4.5, gy + pillar.y * 0.5, gz), pillar, Vector3.ZERO, _frame_mat, 1)
	add_static_box(props, Vector3(gx, gy + 9.4, gz), Vector3(11.0, 1.0, 1.4), Vector3.ZERO, _frame_mat, 1)

	# 枠を縁取る光の管
	var tube_color := Color(0.17, 0.90, 1.00)
	var tube_mat := _emissive_material(tube_color, 3.0)
	for side in [-1.0, 1.0]:
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.22, 8.8, 0.22)
		mi.mesh = mesh
		mi.material_override = tube_mat
		mi.position = Vector3(gx + side * 3.8, gy + 4.4, gz)
		props.add_child(mi)
	var top := MeshInstance3D.new()
	var top_mesh := BoxMesh.new()
	top_mesh.size = Vector3(7.8, 0.22, 0.22)
	top.mesh = top_mesh
	top.material_override = tube_mat
	top.position = Vector3(gx, gy + 8.8, gz)
	props.add_child(top)

	# 中の光の膜（くぐる場所を示す）
	var veil := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(7.4, 8.6)
	veil.mesh = quad
	var veil_mat := StandardMaterial3D.new()
	veil_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	veil_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	veil_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	veil_mat.albedo_color = Color(0.55, 0.95, 1.0, 0.16)
	veil_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	veil_mat.disable_fog = true
	veil.material_override = veil_mat
	veil.position = Vector3(gx, gy + 4.4, gz)
	props.add_child(veil)

	# フォグに消えない光の暈（遠くからでも「あそこに何かある」と分かる目印）
	var halo := MeshInstance3D.new()
	var halo_quad := QuadMesh.new()
	halo_quad.size = Vector2(26.0, 26.0)
	halo.mesh = halo_quad
	var halo_mat := StandardMaterial3D.new()
	halo_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	halo_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	halo_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	halo_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	halo_mat.disable_fog = true
	var grad := Gradient.new()
	grad.set_color(0, Color(0.45, 0.95, 1.0, 0.5))
	grad.set_color(1, Color(0.45, 0.95, 1.0, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 64
	tex.height = 64
	halo_mat.albedo_texture = tex
	halo.material_override = halo_mat
	halo.position = Vector3(gx, gy + 4.6, gz)
	props.add_child(halo)

	var light := OmniLight3D.new()
	light.light_color = tube_color
	light.light_energy = 3.0
	light.omni_range = 26.0
	light.position = Vector3(gx, gy + 4.5, gz)
	props.add_child(light)

	add_portal(Vector3(gx, gy + 1.0, gz), gate_next_world, Color(0.75, 0.97, 1.0),
		light, tube_mat, halo, gate_glow_radius, gate_enter_radius)


func _setup_hum() -> void:
	var stream := hum.stream
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	hum.volume_db = Tuning.ambient_volume_db
	hum.play()
