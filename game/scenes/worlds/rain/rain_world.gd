extends WorldBase
## 最初のワールド「雨の景色」。灰色の空、濡れた地面と水たまりの反射、雨粒、雨音。
## 見つけるもの: 遠く（-Z 方向、約 140m）にぼんやり灯る灯り。飛び石の道がそこへ続く。
## 道沿いには人がいた跡（小屋・柵・消えた街灯）を置く。灯りだけが点いている唯一の光で、
## 街灯はすべて消えている（「あそこにだけ灯りがある」を壊さないため）。
## 灯りは **別のワールドへの入口**。近づくと光が強くなり、触れると白くフェードして次のワールドへ移る。
## 地形の共通部分は world_base.gd。ここではワールド固有の小物と、雨をプレイヤーに追従させる。

const RAIN_MAX_AMOUNT := 2400        # rain_amount = 1.0 のときの粒の数
const RAIN_MAX_AMOUNT_LOW := 700     # 軽くする設定のときの上限（スマホ）

@export_group("雨")
@export var rain_height: float = 9.0        # プレイヤーの頭上どこから降らせるか

@export_group("見つけるもの")
@export var lantern_position: Vector2 = Vector2(6.0, -140.0)
@export var lantern_glow_radius: float = 14.0   # この距離から光が強くなり始める m
@export var lantern_enter_radius: float = 3.0   # この距離まで近づくと次のワールドへ m
@export var lantern_next_world: String = "res://scenes/worlds/neon/neon_world.tscn"

@onready var props: Node3D = $Props
@onready var rain: CPUParticles3D = $Rain
@onready var rain_sound: AudioStreamPlayer = $RainSound

var _rock_mat: StandardMaterial3D
var _post_mat: StandardMaterial3D
var _stone_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D   # 小屋の壁
var _roof_mat: StandardMaterial3D   # 小屋の屋根
var _dark_mat: StandardMaterial3D   # 戸口・窓の暗がり
var _gutters: Array[GPUParticles3D] = []


func _ready() -> void:
	super()
	_setup_rain_sound()


func _process(delta: float) -> void:
	super(delta)
	# 雨はプレイヤーの周りだけに降らせる（遠くは見えないので無駄にしない）
	rain.global_position = player.global_position + Vector3(0.0, rain_height, 0.0)
	rain_sound.volume_db = Tuning.ambient_volume_db + linear_to_db(clampf(0.25 + 0.75 * Tuning.rain_amount, 0.05, 1.0))
	# F1 の値を反映（雨の量・水たまり）
	var cap := RAIN_MAX_AMOUNT_LOW if Tuning.low_quality() else RAIN_MAX_AMOUNT
	var want_amount := maxi(int(cap * Tuning.rain_amount), 1)
	if rain.amount != want_amount:
		rain.amount = want_amount   # 個数を変えると粒が撒き直される（スライダーを動かした瞬間だけ途切れる）
		rain.emitting = Tuning.rain_amount > 0.01
		# 雨どいから落ちる水も雨と一緒に止める
		for g in _gutters:
			g.emitting = rain.emitting
	var mat := terrain_mesh.material_override as ShaderMaterial
	if mat:
		if not is_equal_approx(float(mat.get_shader_parameter("puddle_amount")), Tuning.puddle_amount):
			mat.set_shader_parameter("puddle_amount", Tuning.puddle_amount)
		if not is_equal_approx(float(mat.get_shader_parameter("ripple_rate")), Tuning.rain_amount):
			mat.set_shader_parameter("ripple_rate", Tuning.rain_amount)
		var scale := 1.0 / maxf(Tuning.puddle_size, 1.0)
		if not is_equal_approx(float(mat.get_shader_parameter("puddle_scale")), scale):
			mat.set_shader_parameter("puddle_scale", scale)


## 軽くする設定では、地面のシェーダーの手間を減らす（細かいノイズと波紋を省く）
func _on_quality_changed(low: bool) -> void:
	var mat := terrain_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("cheap", low)


func _decorate() -> void:
	_rock_mat = WorldBase.flat_material(Color(0.17, 0.18, 0.20), 0.6)
	_post_mat = WorldBase.flat_material(Color(0.12, 0.12, 0.13), 0.7)
	_stone_mat = WorldBase.flat_material(Color(0.30, 0.31, 0.34), 0.35)
	_wall_mat = WorldBase.flat_material(Color(0.225, 0.240, 0.270), 0.75)
	_roof_mat = WorldBase.flat_material(Color(0.150, 0.160, 0.185), 0.55)
	_dark_mat = WorldBase.flat_material(Color(0.055, 0.060, 0.070), 0.9)
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
	# 道が決まってから、道を塞がない位置に人がいた跡を置く
	_build_huts(rng)
	_build_fences(rng)
	_build_lamp_posts()


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
	# 灯りは別のワールドへの入口
	add_portal(Vector3(gx, gy + 1.0, gz), lantern_next_world, Color(1.0, 0.93, 0.8),
		light, lamp_mat, halo, lantern_glow_radius, lantern_enter_radius)


# ---------------------------------------------------------------- 人がいた跡
## 飛び石の道までの距離 m。小物が道を塞がないようにするために使う
func _distance_to_path(x: float, z: float) -> float:
	var a := Vector2(0.0, -4.0)
	var b := lantern_position
	var ab := b - a
	var t := clampf((Vector2(x, z) - a).dot(ab) / ab.length_squared(), 0.0, 1.0)
	return Vector2(x, z).distance_to(a + ab * t)


## 小屋。箱の壁 + 三角柱の屋根 + 暗い戸口。道沿いに数軒と、霧の奥に何軒か。
## 道の近くの 1 軒は雨どいから水が落ちる
func _build_huts(rng: RandomNumberGenerator) -> void:
	var placed: Array[Vector2] = []
	var near_path := 0
	var tries := 0
	while placed.size() < 9 and tries < 400:
		tries += 1
		var x := rng.randf_range(-120.0, 120.0)
		var z := rng.randf_range(-165.0, 90.0)
		var to_path := _distance_to_path(x, z)
		# 道から 8〜45m。近すぎると通れなくなり、遠すぎると気づかれない
		if to_path < 8.0 or to_path > 45.0 or Vector2(x, z).length() < 18.0:
			continue
		var too_close := false
		for q in placed:
			if q.distance_to(Vector2(x, z)) < 26.0:
				too_close = true
				break
		if too_close:
			continue
		placed.append(Vector2(x, z))
		var with_gutter := to_path < 16.0 and near_path < 2
		if with_gutter:
			near_path += 1
		_build_hut(rng, x, z, with_gutter)


func _build_hut(rng: RandomNumberGenerator, x: float, z: float, with_gutter: bool) -> void:
	var w := rng.randf_range(3.6, 5.4)
	var d := rng.randf_range(3.0, 4.6)
	var h := rng.randf_range(2.3, 3.0)
	var yaw := rng.randf_range(0.0, TAU)
	var gy := get_ground_height(x, z)
	var base := Vector3(x, gy, z)
	add_static_box(props, base + Vector3(0, h * 0.5, 0), Vector3(w, h, d), Vector3(0, yaw, 0), _wall_mat, 1)
	# 三角の屋根（PrismMesh は上が尖った三角柱。奥行きに沿って棟が通る）
	var roof := PrismMesh.new()
	roof.size = Vector3(w + 0.8, 1.5, d + 0.9)
	var roof_shape := BoxShape3D.new()
	roof_shape.size = Vector3(w + 0.8, 1.5, d + 0.9)
	add_static_mesh(props, base + Vector3(0, h + 0.75, 0), roof, roof_shape, Vector3(0, yaw, 0), _roof_mat, 1)
	# 戸口（暗いだけの板。中には入れない）
	var front := Vector3(sin(yaw), 0.0, cos(yaw))
	var door := MeshInstance3D.new()
	var door_mesh := BoxMesh.new()
	door_mesh.size = Vector3(0.9, 1.6, 0.08)
	door.mesh = door_mesh
	door.material_override = _dark_mat
	door.position = base + Vector3(0, 0.8, 0) + front * (d * 0.5 + 0.05)
	door.rotation = Vector3(0, yaw, 0)
	props.add_child(door)
	if with_gutter:
		var along := Vector3(sin(yaw + PI * 0.5), 0, cos(yaw + PI * 0.5))
		_build_gutter(base, yaw, front, along, w, d, h)
		_build_umbrella_stand(rng, base + front * (d * 0.5 + 0.7) - along * (w * 0.32))


## 軒先の雨どいと、その吐き口から落ちる水。樋が見えていないと、ただの雨粒と見分けが付かない。
## 水は F1 で雨を止めると一緒に止まる
func _build_gutter(base: Vector3, yaw: float, front: Vector3, along: Vector3,
		w: float, d: float, h: float) -> void:
	var eave := base + front * (d * 0.5 + 0.4) + Vector3(0, h + 0.02, 0)
	# 軒に沿って渡した樋
	add_static_box(props, eave, Vector3(0.14, 0.14, w + 0.7), Vector3(0, atan2(along.x, along.z), 0), _post_mat)
	# 端の吐き口（短く下に突き出す）
	var spout := eave + along * (w * 0.42) + Vector3(0, -0.22, 0)
	add_static_box(props, spout, Vector3(0.12, 0.44, 0.12), Vector3.ZERO, _post_mat)
	var pos := Vector3(spout.x, base.y, spout.z)
	var from_height := spout.y - 0.22 - base.y
	var p := GPUParticles3D.new()
	p.position = pos + Vector3(0, from_height, 0)
	p.amount = 40
	p.lifetime = 0.8
	p.preprocess = 1.0
	p.visibility_aabb = AABB(Vector3(-1, -from_height - 1, -1), Vector3(2, from_height + 2, 2))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(0.035, 0.01, 0.035)
	pm.direction = Vector3(0, -1, 0)
	pm.spread = 1.5
	pm.initial_velocity_min = 1.8
	pm.initial_velocity_max = 2.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.7
	pm.scale_max = 1.2
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.075, 0.5)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.82, 0.86, 0.92, 0.75)
	quad.material = mat
	p.draw_pass_1 = quad
	props.add_child(p)
	_gutters.append(p)

	# 落ちた先の水たまり（濡れて光る小さな円）
	var splash := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.75
	disc.bottom_radius = 0.75
	disc.height = 0.02
	disc.radial_segments = 12
	splash.mesh = disc
	var splash_mat := WorldBase.flat_material(Color(0.36, 0.39, 0.44), 0.08)
	splash_mat.metallic = 0.4
	splash.material_override = splash_mat
	splash.position = Vector3(pos.x, get_ground_height(pos.x, pos.z) + 0.015, pos.z)
	props.add_child(splash)


## 戸口の脇の傘立て。傘が何本か挿さったまま残っている（人がいた気配の小さな印）
func _build_umbrella_stand(rng: RandomNumberGenerator, pos: Vector3) -> void:
	var gy := get_ground_height(pos.x, pos.z)
	var barrel := CylinderMesh.new()
	barrel.top_radius = 0.26
	barrel.bottom_radius = 0.24
	barrel.height = 0.55
	barrel.radial_segments = 10
	var shape := CylinderShape3D.new()
	shape.radius = 0.26
	shape.height = 0.55
	add_static_mesh(props, Vector3(pos.x, gy + 0.275, pos.z), barrel, shape, Vector3.ZERO, _post_mat)
	for i in 3:
		var lean := rng.randf_range(0.10, 0.26)
		var dir := rng.randf_range(0.0, TAU)
		var h := rng.randf_range(0.8, 1.0)
		var off := Vector2(sin(dir), cos(dir)) * (sin(lean) * h * 0.5)
		add_static_box(props, Vector3(pos.x + off.x, gy + 0.45 + cos(lean) * h * 0.5, pos.z + off.y),
			Vector3(0.07, h, 0.07), Vector3(cos(dir) * lean, 0.0, -sin(dir) * lean), _dark_mat)


## 柵。道の脇に短く何本か。腰の高さなので歩いて回り込める
func _build_fences(rng: RandomNumberGenerator) -> void:
	for i in 7:
		var t := rng.randf_range(0.08, 0.92)
		var along := Vector2(0.0, -4.0).lerp(lantern_position, t)
		var dir := (lantern_position - Vector2(0.0, -4.0)).normalized()
		var side := Vector2(-dir.y, dir.x) * (1.0 if rng.randf() < 0.5 else -1.0)
		var origin := along + side * rng.randf_range(7.0, 13.0)
		var yaw := rng.randf_range(0.0, TAU)
		var forward := Vector2(sin(yaw), cos(yaw))
		var span := rng.randi_range(4, 7)
		for seg in span:
			var p := origin + forward * (seg * 1.7)
			var gy := get_ground_height(p.x, p.y)
			add_static_box(props, Vector3(p.x, gy + 0.55, p.y), Vector3(0.12, 1.1, 0.12), Vector3.ZERO, _post_mat)
			if seg == span - 1:
				continue
			var mid := p + forward * 0.85
			var my := get_ground_height(mid.x, mid.y)
			for rail_y in [0.42, 0.88]:
				add_static_box(props, Vector3(mid.x, my + rail_y, mid.y), Vector3(0.06, 0.09, 1.7),
					Vector3(0, yaw, 0), _post_mat)


## 消えた街灯。道沿いに等間隔で並べ、霧の奥へ続く線を作る（どこへ向かうかの案内になる）。
## 光らせないのは、点いている灯りが 1 つだけという「見つけるもの」を壊さないため
func _build_lamp_posts() -> void:
	var start := Vector2(0.0, -4.0)
	var goal := lantern_position
	var dir := (goal - start).normalized()
	var side := Vector2(-dir.y, dir.x)
	var dist := start.distance_to(goal)
	var d := 16.0
	var flip := 1.0
	while d < dist - 12.0:
		var p := start + dir * d + side * (flip * 3.6 + sin(d * 0.12) * 2.5)
		var gy := get_ground_height(p.x, p.y)
		add_static_box(props, Vector3(p.x, gy + 1.7, p.y), Vector3(0.16, 3.4, 0.16), Vector3.ZERO, _post_mat, 1)
		# 先端の腕と、消えた笠。腕は道の側へ差し出す
		var arm := side * -flip
		var arm_yaw := atan2(arm.x, arm.y)
		add_static_box(props, Vector3(p.x + arm.x * 0.35, gy + 3.35, p.y + arm.y * 0.35),
			Vector3(0.1, 0.1, 0.7), Vector3(0, arm_yaw, 0), _post_mat)
		add_static_box(props, Vector3(p.x + arm.x * 0.7, gy + 3.15, p.y + arm.y * 0.7),
			Vector3(0.44, 0.4, 0.44), Vector3.ZERO, _dark_mat)
		d += 24.0
		flip = -flip


func _setup_rain_sound() -> void:
	var stream := rain_sound.stream
	if stream is AudioStreamWAV:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = int(stream.get_length() * stream.mix_rate)
	rain_sound.volume_db = Tuning.ambient_volume_db
	rain_sound.play()
