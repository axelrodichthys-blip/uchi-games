extends WorldBase
## 2 つ目のワールド「ネオン」。暗闇に光る看板、濡れた路面の映り込み、電子音。
## 見つけるもの: 道の突き当たり（-Z 方向、約 150m）に光るゲート。くぐると「雨の景色」へ戻る。
## 地形の共通部分は world_base.gd。ここでは街の中身を組み立てる。
##
## 街の中身:
##   - 道の両側のビル（窓明かり付き）と、文字らしい形に光る看板
##   - 横道の路地（行き止まり。奥に自販機の灯りと蒸気。大通りから見えるので「入ってみたくなる」）
##   - 路面の湯気（マンホールと路地の排気口）
##   - 通行人の影（黒いシルエットが歩道を行き来する。当たり判定は無し）
##   - 突き当たりの光るゲート（別のワールドへの入口）
##
## 描画の負荷を抑えるため、看板・窓は色ごとに 1 つのメッシュにまとめてから置く
## （小さな板を数百枚ぶら下げると内蔵 GPU とスマホで重くなるため）。
##
## 色（3〜5 色で統一する）:
##   闇 #07080F / ビル #12141F / ピンク #FF3D80 / シアン #2BE6FF / 黄 #FFD447

const STREET_HALF := 9.0        # 道の半分の幅 m
const BLOCK := 13.0             # ビル（看板）の間隔 m。シェーダーの sign_spacing と合わせる
const NEON_COLORS := [Color(1.00, 0.24, 0.50), Color(0.17, 0.90, 1.00), Color(1.00, 0.83, 0.28)]
const WINDOW_COLOR := Color(1.00, 0.82, 0.55)   # 窓明かり（弱い電球色）
const BULB_COLOR := Color(1.00, 0.76, 0.45)     # 路地に吊るした裸電球
const WALK_RANGE := 55.0        # 通行人がいる範囲（プレイヤーの前後 m）。これを超えたら反対側へ回す

# 路地。地形を平らにする必要があるので、地形生成より前に決まっている必要がある（乱数は使わない）
const ALLEY_HALF_WIDTH := 2.9    # 路地の半分の幅 m
const ALLEY_LENGTH := 24.0       # 道の端から奥までの長さ m
const ALLEYS := [
	{"z": -104.0, "side": 1.0},
	{"z": -46.0, "side": -1.0},
	{"z": 22.0, "side": 1.0},
	{"z": 78.0, "side": -1.0},
]

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
var _panel_mat: StandardMaterial3D      # 看板の下地（消えている部分）

# まとめて 1 メッシュにするための入れ物
var _neon_st: Array[SurfaceTool] = []
var _neon_used: Array[bool] = []
var _panel_st: SurfaceTool
var _panel_used: bool = false
var _window_st: SurfaceTool
var _window_used: bool = false
var _bulb_st: SurfaceTool
var _bulb_used: bool = false
var _box := BoxMesh.new()

var _steam: Array[GPUParticles3D] = []
var _walkers: Array[Dictionary] = []
var _walk_limit: float = 0.0


## 道は平ら。路地の帯も奥まで平らにし、そこから外はゆるやかに起伏させる
func _terrain_height(x: float, z: float) -> float:
	var away := smoothstep(STREET_HALF + 14.0, STREET_HALF + 60.0, absf(x))
	away *= 1.0 - _alley_flat(x, z)
	return _noise.get_noise_2d(x, z) * hill_height * away


## 路地の内側なら 1.0（平ら）、外に向かって 0 に戻る
func _alley_flat(x: float, z: float) -> float:
	var flat := 0.0
	for alley in ALLEYS:
		if signf(x) != float(alley["side"]):
			continue
		var across := 1.0 - smoothstep(ALLEY_HALF_WIDTH + 2.0, ALLEY_HALF_WIDTH + 9.0, absf(z - float(alley["z"])))
		var along := 1.0 - smoothstep(STREET_HALF + ALLEY_LENGTH + 2.0, STREET_HALF + ALLEY_LENGTH + 10.0, absf(x))
		flat = maxf(flat, across * along)
	return flat


func _ready() -> void:
	super()
	_setup_hum()


func _process(delta: float) -> void:
	super(delta)
	hum.volume_db = Tuning.ambient_volume_db
	var mat := terrain_mesh.material_override as ShaderMaterial
	if mat and not is_equal_approx(float(mat.get_shader_parameter("puddle_amount")), Tuning.puddle_amount):
		mat.set_shader_parameter("puddle_amount", Tuning.puddle_amount)
	for p in _steam:
		if not is_equal_approx(p.amount_ratio, Tuning.steam_amount):
			p.amount_ratio = clampf(Tuning.steam_amount, 0.0, 1.0)
			p.emitting = Tuning.steam_amount > 0.01
	_move_walkers(delta)


## 軽くする設定では、地面のシェーダーの手間を減らす
func _on_quality_changed(low: bool) -> void:
	var mat := terrain_mesh.material_override as ShaderMaterial
	if mat:
		mat.set_shader_parameter("cheap", low)


func _decorate() -> void:
	_building_mat = WorldBase.flat_material(Color(0.07, 0.08, 0.12), 0.85)
	_frame_mat = WorldBase.flat_material(Color(0.04, 0.045, 0.06), 0.7)
	_panel_mat = WorldBase.flat_material(Color(0.025, 0.028, 0.038), 0.6)
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed + 7
	if Tuning.low_quality():
		street_lights = maxi(street_lights / 2, 3)   # スマホでは光源を減らす
	_begin_merged_meshes()
	_build_street(rng)
	_build_alleys(rng)
	_commit_merged_meshes()
	_build_gate()
	_build_steam()
	_build_walkers(rng)


# ---------------------------------------------------------------- まとめメッシュ
func _begin_merged_meshes() -> void:
	_neon_st.clear()
	_neon_used.clear()
	for i in NEON_COLORS.size():
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		_neon_st.append(st)
		_neon_used.append(false)
	_panel_st = SurfaceTool.new()
	_panel_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_window_st = SurfaceTool.new()
	_window_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_bulb_st = SurfaceTool.new()
	_bulb_st.begin(Mesh.PRIMITIVE_TRIANGLES)


## 箱 1 つぶんの面を、まとめメッシュに足す
func _add_box(st: SurfaceTool, center: Vector3, size: Vector3) -> void:
	_box.size = size
	st.append_from(_box, 0, Transform3D(Basis(), center))


func _add_neon_box(color_index: int, center: Vector3, size: Vector3) -> void:
	_add_box(_neon_st[color_index], center, size)
	_neon_used[color_index] = true


func _commit_merged_meshes() -> void:
	for i in _neon_st.size():
		if not _neon_used[i]:
			continue
		_add_merged(_neon_st[i], _emissive_material(NEON_COLORS[i], 2.4))
	if _panel_used:
		_add_merged(_panel_st, _panel_mat)
	if _window_used:
		_add_merged(_window_st, _emissive_material(WINDOW_COLOR, 0.55))
	if _bulb_used:
		_add_merged(_bulb_st, _emissive_material(BULB_COLOR, 2.0))


func _add_merged(st: SurfaceTool, mat: Material) -> void:
	var mesh := st.commit()
	if mesh == null or mesh.get_surface_count() == 0:
		return
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	props.add_child(mi)


# ---------------------------------------------------------------- 大通り
## 道の両側にビルを建て、道に面した壁に光る看板と窓明かりを付ける
func _build_street(rng: RandomNumberGenerator) -> void:
	var z := -street_length
	var light_every := maxi(int((street_length * 2.0 / BLOCK) / maxf(street_lights, 1.0)), 1)
	var index := 0
	while z < street_length:
		var depth := rng.randf_range(10.0, 18.0)
		var zc := z + BLOCK * 0.5
		for side in [-1.0, 1.0]:
			if _alley_mouth_at(side, zc):
				continue   # ここは路地の入口。ビルを建てない
			var width := rng.randf_range(BLOCK * 0.65, BLOCK * 0.95)
			var height := rng.randf_range(10.0, 34.0)
			var x: float = side * (STREET_HALF + 1.0 + depth * 0.5)
			var center := Vector3(x, height * 0.5, zc)
			add_static_box(props, center, Vector3(depth, height, width), Vector3.ZERO, _building_mat, 1)
			# 屋上の縁（暗い帯）で輪郭を出す
			add_static_box(props, center + Vector3(0, height * 0.5 + 0.3, 0), Vector3(depth + 0.6, 0.6, width + 0.6), Vector3.ZERO, _frame_mat, 1)
			var face_x: float = x - side * (depth * 0.5 + 0.08)
			_add_windows(rng, face_x, side, height, zc, width)
			_add_signs(rng, side, face_x, height, zc, width, index % light_every == 0)
		z += BLOCK
		index += 1


## この場所が路地の入口にあたるか（ビルを建てない範囲）
func _alley_mouth_at(side: float, z: float) -> bool:
	for alley in ALLEYS:
		if float(alley["side"]) == side and absf(z - float(alley["z"])) < ALLEY_HALF_WIDTH + BLOCK * 0.5:
			return true
	return false


## ビルの壁の窓明かり。等間隔に並べ、一部だけ点ける（人が住んでいる気配）
func _add_windows(rng: RandomNumberGenerator, face_x: float, side: float, height: float, z: float, width: float) -> void:
	var step_z := 2.1
	var cols := maxi(int((width - 1.6) / step_z), 1)
	var rows := maxi(int((height - 5.0) / 2.9), 0)
	var lit_chance := 0.22 if Tuning.low_quality() else 0.34
	for row in rows:
		var y := 4.2 + row * 2.9
		for col in cols:
			if rng.randf() > lit_chance:
				continue
			var wz := z - (cols - 1) * step_z * 0.5 + col * step_z
			for pane in [-1.0, 1.0]:
				var pz: float = wz + float(pane) * 0.21
				_add_box(_window_st, Vector3(face_x - side * 0.04, y, pz), Vector3(0.1, 0.92, 0.34))
			_window_used = true


## ビル 1 棟ぶんの看板。縦長・横長をいくつか。光源は数を絞って置く
func _add_signs(rng: RandomNumberGenerator, side: float, face_x: float, height: float, z: float, width: float, with_light: bool) -> void:
	var count := rng.randi_range(1, 3)
	var brightest := Color.BLACK
	var brightest_y := 0.0
	for i in count:
		var color_index := rng.randi_range(0, NEON_COLORS.size() - 1)
		var vertical := rng.randf() < 0.55
		var cell := rng.randf_range(0.8, 1.15)
		var chars := rng.randi_range(2, 4)
		var top_y := rng.randf_range(5.0, maxf(height - 2.0, 6.0))
		if vertical:
			top_y = maxf(top_y, chars * cell + 3.0)
		var zc := z + rng.randf_range(-width * 0.22, width * 0.22)
		_add_glyph_sign(rng, color_index, face_x, side, top_y, zc, chars, cell, vertical)
		var mid_y := top_y - (chars * cell * 0.5 if vertical else cell * 0.5)
		if mid_y > brightest_y:
			brightest_y = mid_y
			brightest = NEON_COLORS[color_index]
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = brightest
		light.light_energy = 4.5
		light.omni_range = 30.0
		light.omni_attenuation = 1.2
		light.position = Vector3(face_x - side * 3.5, clampf(brightest_y, 3.0, 10.0), z)
		props.add_child(light)


# ---------------------------------------------------------------- 看板（文字らしい形）
## 看板 1 枚。下地の板の上に、文字のような線（横棒 + 縦棒 + 囲い）を並べる。
## 文字そのものは描かず「漢字・仮名っぽい線の並び」に見せる（フォントを持たずに済む）。
##   top_y: 看板の上端の高さ、z_center: 道に沿った位置、chars: 字数、cell: 1 字の大きさ m
func _add_glyph_sign(rng: RandomNumberGenerator, color_index: int, face_x: float, side: float,
		top_y: float, z_center: float, chars: int, cell: float, vertical: bool) -> void:
	var sign_h: float = chars * cell if vertical else cell
	var sign_w: float = cell if vertical else chars * cell
	var margin := cell * 0.22
	var center_y := top_y - sign_h * 0.5
	# 下地（消えている部分。これがあると光る線が「文字」に見える）
	_add_box(_panel_st, Vector3(face_x, center_y, z_center),
		Vector3(0.22, sign_h + margin, sign_w + margin))
	_panel_used = true
	# 枠（外周の光の線）
	var frame := cell * 0.09
	var glyph_x := face_x - side * 0.15
	if rng.randf() < 0.5:
		var hw := sign_w * 0.5 + margin * 0.4
		var hh := sign_h * 0.5 + margin * 0.4
		_add_neon_box(color_index, Vector3(glyph_x, center_y + hh, z_center), Vector3(0.14, frame, hw * 2.0))
		_add_neon_box(color_index, Vector3(glyph_x, center_y - hh, z_center), Vector3(0.14, frame, hw * 2.0))
		_add_neon_box(color_index, Vector3(glyph_x, center_y, z_center + hw), Vector3(0.14, hh * 2.0, frame))
		_add_neon_box(color_index, Vector3(glyph_x, center_y, z_center - hw), Vector3(0.14, hh * 2.0, frame))
	# 1 字ずつ
	for i in chars:
		var cy: float = top_y - (i + 0.5) * cell if vertical else center_y
		var cz: float = z_center if vertical else z_center - sign_w * 0.5 + (i + 0.5) * cell
		_add_glyph(rng, color_index, glyph_x, cy, cz, cell * 0.74)


## 1 字ぶんの線を引く。横棒を 2〜3 本、多くは縦棒 1 本、ときどき囲い（口・国のような形）
func _add_glyph(rng: RandomNumberGenerator, color_index: int, gx: float, cy: float, cz: float, size: float) -> void:
	var stroke := size * 0.15
	var kind := rng.randi_range(0, 3)
	var bars := rng.randi_range(2, 3)
	for i in bars:
		var t := (i + 1.0) / (bars + 1.0)
		var y := cy + size * (0.5 - t)
		var w := size * rng.randf_range(0.55, 0.95)
		_add_neon_box(color_index, Vector3(gx, y, cz), Vector3(0.14, stroke, w))
	if kind != 3:
		var vz := cz + size * rng.randf_range(-0.16, 0.16)
		var vh := size * rng.randf_range(0.6, 0.88)
		_add_neon_box(color_index, Vector3(gx, cy, vz), Vector3(0.14, vh, stroke))
	if kind == 2:
		var half := size * 0.34
		for s in [-1.0, 1.0]:
			_add_neon_box(color_index, Vector3(gx, cy, cz + float(s) * half), Vector3(0.14, size * 0.66, stroke))


# ---------------------------------------------------------------- 路地
## 大通りから横に伸びる行き止まりの小道。奥に自販機の灯りがあり、大通りからも見える
func _build_alleys(rng: RandomNumberGenerator) -> void:
	for alley in ALLEYS:
		var side := float(alley["side"])
		var az := float(alley["z"])
		var inner := STREET_HALF + 1.0
		var outer := STREET_HALF + ALLEY_LENGTH
		var length := outer - inner
		var cx := side * (inner + length * 0.5)
		# 両側の壁（背の低い雑居ビル。大通り側ほど高くして、奥がすぼまって見えるようにする）
		for wall_side in [-1.0, 1.0]:
			var wz: float = az + float(wall_side) * (ALLEY_HALF_WIDTH + 2.5)
			var h := rng.randf_range(11.0, 18.0)
			add_static_box(props, Vector3(cx, h * 0.5, wz), Vector3(length, h, 5.0), Vector3.ZERO, _building_mat, 1)
			add_static_box(props, Vector3(cx, h + 0.3, wz), Vector3(length + 0.4, 0.6, 5.4), Vector3.ZERO, _frame_mat, 1)
		# 行き止まりの壁
		var back_h := rng.randf_range(13.0, 20.0)
		add_static_box(props, Vector3(side * (outer + 1.5), back_h * 0.5, az),
			Vector3(3.0, back_h, ALLEY_HALF_WIDTH * 2.0 + 10.0), Vector3.ZERO, _building_mat, 1)
		_build_vending(side, outer, az)
		_build_alley_bulbs(side, inner, outer, az)
		_build_alley_props(rng, side, inner, outer, az)


## 路地に吊るした裸電球の列。大通りからは「暗がりに点々と灯りが続く」形に見えるので、
## 光源を足さずに（内蔵 GPU のため）路地へ誘い込む目印になる
func _build_alley_bulbs(side: float, inner: float, outer: float, az: float) -> void:
	var y := 3.4
	var start := inner - 1.6   # 少しだけ大通りにはみ出させる
	var stop := outer - 2.5
	# 電球を吊るす線（暗い細い棒）
	var length := stop - start
	_add_box(_panel_st, Vector3(side * (start + length * 0.5), y + 0.16, az), Vector3(length, 0.05, 0.05))
	_panel_used = true
	var step := 2.4
	var count := maxi(int(length / step), 1)
	for i in count + 1:
		var bx: float = side * (start + i * step)
		_add_box(_bulb_st, Vector3(bx, y, az), Vector3(0.17, 0.17, 0.17))
		_bulb_used = true


## 路地の奥の自販機。暖色の光が路地を照らし、大通りから「奥に何かある」と分かる目印になる
func _build_vending(side: float, outer: float, az: float) -> void:
	var x := side * (outer - 1.4)
	var front_x := x - side * 0.38
	var body := Vector3(0.8, 1.9, 1.15)
	add_static_box(props, Vector3(x, 0.95, az), body, Vector3.ZERO, _frame_mat, 4)
	# 光る前面
	var glass := MeshInstance3D.new()
	var glass_mesh := BoxMesh.new()
	glass_mesh.size = Vector3(0.08, 1.5, 0.95)
	glass.mesh = glass_mesh
	glass.material_override = _emissive_material(Color(1.0, 0.93, 0.78), 0.5)
	glass.position = Vector3(front_x, 1.05, az)
	props.add_child(glass)
	# 並んだ商品（小さな色の点）
	for row in 3:
		for col in 4:
			var c: Color = NEON_COLORS[(row + col) % NEON_COLORS.size()]
			var item := MeshInstance3D.new()
			var item_mesh := BoxMesh.new()
			item_mesh.size = Vector3(0.06, 0.16, 0.13)
			item.mesh = item_mesh
			item.material_override = _emissive_material(c, 1.5)
			item.position = Vector3(front_x - side * 0.05, 1.5 - row * 0.32, az - 0.33 + col * 0.22)
			props.add_child(item)
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.86, 0.62)
	light.light_energy = 2.2
	light.omni_range = 16.0
	light.position = Vector3(front_x - side * 1.0, 1.6, az)
	props.add_child(light)


## 路地に散らかっているもの（箱・ドラム缶・室外機）。歩く邪魔にならない位置に置く
func _build_alley_props(rng: RandomNumberGenerator, side: float, inner: float, outer: float, az: float) -> void:
	var count := rng.randi_range(4, 7)
	for i in count:
		var d := rng.randf_range(inner + 2.0, outer - 3.5)
		var wall_side: float = 1.0 if rng.randf() < 0.5 else -1.0
		var wz := az + wall_side * rng.randf_range(ALLEY_HALF_WIDTH - 1.1, ALLEY_HALF_WIDTH - 0.3)
		var h := rng.randf_range(0.5, 1.1)
		var w := rng.randf_range(0.6, 1.0)
		add_static_box(props, Vector3(side * d, h * 0.5, wz), Vector3(w, h, w),
			Vector3(0, rng.randf_range(-0.4, 0.4), 0), _frame_mat, 4)


# ---------------------------------------------------------------- 湯気
## マンホールと路地の排気口から立ちのぼる湯気。F1 の steam_amount で量を変えられる
func _build_steam() -> void:
	var spots: Array[Vector3] = [
		Vector3(-3.5, 0.0, -28.0),
		Vector3(4.0, 0.0, 44.0),
		Vector3(-2.0, 0.0, -118.0),
	]
	for alley in ALLEYS:
		var side := float(alley["side"])
		spots.append(Vector3(side * (STREET_HALF + 9.0), 0.0, float(alley["z"]) + 1.4))
	var low := Tuning.low_quality()
	var kept := spots.size() / 2 if low else spots.size()
	for i in spots.size():
		if i >= kept:
			break
		var pos: Vector3 = spots[i]
		pos.y = get_ground_height(pos.x, pos.z)
		_add_manhole(pos)
		_steam.append(_make_steam(pos + Vector3(0, 0.15, 0), 14 if low else 26))


func _add_manhole(pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.42
	mesh.bottom_radius = 0.42
	mesh.height = 0.06
	mesh.radial_segments = 10
	mi.mesh = mesh
	mi.material_override = _frame_mat
	mi.position = pos + Vector3(0, 0.03, 0)
	props.add_child(mi)


## 中心が濃く縁に向かって消えていく丸。湯気の粒とゲートの暈に使う
static func _radial_texture(color: Color, size: int = 64) -> GradientTexture2D:
	var grad := Gradient.new()
	grad.set_color(0, Color(color.r, color.g, color.b, 1.0))
	grad.set_color(1, Color(color.r, color.g, color.b, 0.0))
	var tex := GradientTexture2D.new()
	tex.gradient = grad
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = size
	tex.height = size
	return tex


func _make_steam(pos: Vector3, amount: int) -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = pos
	p.amount = amount
	p.lifetime = 4.5
	p.preprocess = 2.0
	p.randomness = 0.5
	p.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 10, 8))

	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.3
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 14.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.3
	pm.gravity = Vector3(0.15, 0.35, 0.0)
	pm.scale_min = 1.4
	pm.scale_max = 3.4
	var grow := Curve.new()
	grow.add_point(Vector2(0.0, 0.25))
	grow.add_point(Vector2(1.0, 1.0))
	var grow_tex := CurveTexture.new()
	grow_tex.curve = grow
	pm.scale_curve = grow_tex
	# 出た瞬間は薄く、少し濃くなってから消える
	var grad := Gradient.new()
	grad.set_color(0, Color(0.72, 0.76, 0.86, 0.0))
	grad.set_color(1, Color(0.72, 0.76, 0.86, 0.0))
	grad.add_point(0.25, Color(0.78, 0.82, 0.92, 0.22))
	grad.add_point(0.6, Color(0.7, 0.74, 0.85, 0.13))
	var ramp := GradientTexture1D.new()
	ramp.gradient = grad
	pm.color_ramp = ramp
	p.process_material = pm

	var quad := QuadMesh.new()
	quad.size = Vector2(1.6, 1.6)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color(1, 1, 1, 1)
	# 板のままだと四角い塊に見えるので、中心が濃く縁が消える丸を貼る
	mat.albedo_texture = _radial_texture(Color(1, 1, 1))
	quad.material = mat
	p.draw_pass_1 = quad

	p.amount_ratio = clampf(Tuning.steam_amount, 0.0, 1.0)
	p.emitting = Tuning.steam_amount > 0.01
	props.add_child(p)
	return p


# ---------------------------------------------------------------- 通行人の影
## 車道の端を行き来する影。当たり判定は持たない（すり抜ける）。
## 通りは 340m あるので、決まった場所に置くと出会えない。プレイヤーから離れたら反対側へ回して、
## どこを歩いていても前後に何人かいる状態にする（人数は増やさない）
func _build_walkers(rng: RandomNumberGenerator) -> void:
	_walk_limit = WALK_RANGE
	# 路面（#13151A あたり）より少し明るい「影の色」。陰影を付けずに切り抜きのシルエットに見せる
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.175, 0.180, 0.225)
	var count := 10
	for i in count:
		var node := _make_walker(mat)
		props.add_child(node)
		var dir: float = 1.0 if rng.randf() < 0.5 else -1.0
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		_walkers.append({
			"node": node,
			"x": side * rng.randf_range(7.0, 9.4),
			"z": player.global_position.z + rng.randf_range(-WALK_RANGE, WALK_RANGE),
			"dir": dir,
			"speed": rng.randf_range(0.9, 1.6),
			"phase": rng.randf_range(0.0, TAU),
			"legs": [node.get_node("L"), node.get_node("R")],
		})
	_apply_crowd()


func _make_walker(mat: Material) -> Node3D:
	var root := Node3D.new()
	var scale_y := 1.0
	_add_walker_part(root, mat, "Body", Vector3(0, 1.08 * scale_y, 0), Vector3(0.42, 0.72, 0.30))
	_add_walker_part(root, mat, "Head", Vector3(0, 1.58 * scale_y, 0), Vector3(0.26, 0.28, 0.26))
	for name in ["L", "R"]:
		var leg := Node3D.new()
		leg.name = name
		leg.position = Vector3(0, 0.72, 0.0)
		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.16, 0.72, 0.18)
		mi.mesh = mesh
		mi.material_override = mat
		mi.position = Vector3(0.0, -0.36, 0.0)
		leg.add_child(mi)
		root.add_child(leg)
	return root


func _add_walker_part(root: Node3D, mat: Material, name: String, pos: Vector3, size: Vector3) -> void:
	var mi := MeshInstance3D.new()
	mi.name = name
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)


## F1 の crowd_amount に合わせて、出す人数を変える
func _apply_crowd() -> void:
	var shown := int(round(_walkers.size() * clampf(Tuning.crowd_amount, 0.0, 1.0)))
	if Tuning.low_quality():
		shown = mini(shown, 4)
	for i in _walkers.size():
		var node: Node3D = _walkers[i]["node"]
		node.visible = i < shown
		node.set_process(i < shown)


func _move_walkers(delta: float) -> void:
	_apply_crowd()
	for w in _walkers:
		var node: Node3D = w["node"]
		if not node.visible:
			continue
		var z: float = w["z"] + float(w["dir"]) * float(w["speed"]) * delta
		# プレイヤーから離れすぎたら反対側へ回す（霧の中なので入れ替わりは見えない）
		var from_player: float = z - player.global_position.z
		if absf(from_player) > _walk_limit:
			z -= signf(from_player) * _walk_limit * 2.0
			z = clampf(z, -street_length, street_length)
		w["z"] = z
		var x: float = w["x"]
		var phase: float = float(w["phase"]) + delta * float(w["speed"]) * 5.0
		w["phase"] = phase
		node.position = Vector3(x, get_ground_height(x, z) + absf(sin(phase)) * 0.035, z)
		node.rotation.y = 0.0 if float(w["dir"]) > 0.0 else PI
		var swing := sin(phase) * 0.45
		node.get_node("L").rotation.x = swing
		node.get_node("R").rotation.x = -swing


# ---------------------------------------------------------------- ゲート
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
	halo_mat.albedo_color = Color(1, 1, 1, 0.5)
	halo_mat.albedo_texture = _radial_texture(Color(0.45, 0.95, 1.0))
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
