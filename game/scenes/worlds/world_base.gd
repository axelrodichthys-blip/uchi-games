class_name WorldBase
extends Node3D
## すべてのワールドの土台。新しいワールドはこれを継承して作る（手順は scenes/worlds/README.md）。
##
## やること:
##   - ノイズで起伏のある地面を作る（出現地点の周り flat_radius は平ら）。高さの式は _terrain_height() で差し替えられる
##   - フォグの濃さを Tuning から毎フレーム反映する（F1 で変えられる）。ワールドごとの初期値は fog_density_default
##   - F2 で次のワールドへ（WorldList）。フェードつきの移動は go_to_world()
##   - 小物を置くときの共通ヘルパー（add_static_box / add_static_mesh）
##   - **世界の端の処理**（一般的なオープンワールドと同じ三段構え）:
##       1. 見せる壁: 地形が端に向かって高く盛り上がり、登れない斜面（slope_max_angle 以上）になって自然に引き返させる
##       2. 見えない壁: 盛り上がりの内側に透明な壁を置き、隙間や小物を伝って越えられないようにする
##       3. 落下の保険: それでも下に落ちたら（バグ・隙間）、暗転して出現地点に戻す
##
## 必要なノード（シーン側で用意する）:
##   WorldEnvironment, DirectionalLight3D, Terrain(StaticBody3D, layer 1) / MeshInstance3D / CollisionShape3D,
##   Player（scenes/player/player.tscn）, HUD, DebugPanel

## 別のワールドへ移り始めたとき（フェードの開始時）。headless テストや演出のつなぎに使う
signal world_changing(scene_path: String)

@export_multiline var hud_hint: String = ""   # HUD の操作案内の末尾に足す、このワールド固有の一言

@export_group("地形")
@export var terrain_size: float = 600.0   # 一辺 m
@export var terrain_cell: float = 3.0     # 頂点の間隔 m
@export var hill_height: float = 10.0     # 丘の高さの目安 m
@export var hill_frequency: float = 0.012 # 小さいほどなだらかで大きな丘
@export var flat_radius: float = 15.0     # この半径までは平ら
@export var terrain_seed: int = 7

@export_group("世界の端")
@export var rim_width: float = 90.0        # 端の盛り上がりが始まる位置（外周からこの幅だけ内側）m
@export var rim_height: float = 120.0      # 端の盛り上がりの高さ m。外側ほど急になり、途中から登れなくなる
@export var rim_variation: float = 0.45    # 端の盛り上がりの起伏（0 で滑らかな器、大きいほど山並みらしくなる）
@export var boundary_inset: float = 25.0   # 見えない壁を外周からどれだけ内側に置くか m（盛り上がりの中、登れない斜面の先）
@export var fall_limit: float = -60.0      # この高さより下に落ちたら出現地点に戻す m

@export_group("風景")
@export var fog_density_default: float = 0.012
@export var footstep_set: String = "stone"   # 足音の組（scenes/player/footsteps.gd の SETS のキー）

@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var terrain_mesh: MeshInstance3D = $Terrain/MeshInstance3D
@onready var terrain_shape: CollisionShape3D = $Terrain/CollisionShape3D
@onready var player: CharacterBody3D = $Player

var _heights: PackedFloat32Array
var _grid_n: int = 0
var _noise: FastNoiseLite
var _rim_noise: FastNoiseLite
var _spawn_point: Vector3
var _fade: ColorRect
var _busy: bool = false   # フェード中（入力とワールド移動を止める）


func _ready() -> void:
	Tuning.fog_density = fog_density_default
	_build_terrain()
	_build_boundary()
	_build_fade()
	_decorate()
	_spawn_point = player.global_position


func _process(_delta: float) -> void:
	var env := environment.environment
	if env and not is_equal_approx(env.fog_density, Tuning.fog_density):
		env.fog_density = Tuning.fog_density
	# 落下の保険: 世界の下に落ちたら出現地点に戻す
	if not _busy and player.global_position.y < fall_limit:
		respawn()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_world"):
		get_viewport().set_input_as_handled()
		go_to_world(WorldList.next_scene(scene_file_path))


# ---------------------------------------------------------------- 世界の端・移動・暗転
## 見えない壁。地形の盛り上がりの内側を四角く囲う（地形と同じレイヤー1 = カメラも避ける）
func _build_boundary() -> void:
	var half := terrain_size * 0.5 - boundary_inset
	if half <= 0.0:
		return
	var walls := Node3D.new()
	walls.name = "Boundary"
	add_child(walls)
	var thickness := 4.0
	var height := maxf(rim_height, 60.0) * 3.0
	var y := height * 0.5 - 40.0   # 下端は地形に埋め、上端は盛り上がりより十分高く
	var dirs := [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]
	for dir in dirs:
		var size := Vector3(thickness, height, half * 2.0 + thickness * 2.0)
		if dir.z != 0.0:
			size = Vector3(half * 2.0 + thickness * 2.0, height, thickness)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		body.position = dir * (half + thickness * 0.5) + Vector3(0, y, 0)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = size
		shape.shape = box
		body.add_child(shape)
		walls.add_child(body)


func _build_fade() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	_fade = ColorRect.new()
	_fade.color = Color(1, 1, 1, 0)
	_fade.anchor_right = 1.0
	_fade.anchor_bottom = 1.0
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(_fade)


## 暗転（既定は白）しながら別のワールドへ移る
func go_to_world(scene_path: String, color: Color = Color(1, 1, 1), fade_time: float = 1.0) -> void:
	if _busy:
		return
	_busy = true
	world_changing.emit(scene_path)
	_fade.color = Color(color.r, color.g, color.b, 0.0)
	var tween := create_tween()
	tween.tween_property(_fade, "color:a", 1.0, fade_time)
	await tween.finished
	get_tree().change_scene_to_file.call_deferred(scene_path)


## 出現地点に戻す（落下の保険）。一瞬だけ暗転する
func respawn() -> void:
	if _busy:
		return
	_busy = true
	var tween := create_tween()
	_fade.color = Color(0, 0, 0, 0)
	tween.tween_property(_fade, "color:a", 1.0, 0.25)
	await tween.finished
	player.global_position = _spawn_point
	player.velocity = Vector3.ZERO
	var back := create_tween()
	back.tween_property(_fade, "color:a", 0.0, 0.5)
	await back.finished
	_busy = false


# ---------------------------------------------------------------- 差し替え用
## 地面の高さ。既定はノイズの丘（出現地点の周りは平ら）。ワールド側で上書きしてよい
func _terrain_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var amp := smoothstep(flat_radius, flat_radius * 3.0, r) * hill_height
	return _noise.get_noise_2d(x, z) * amp


## 小物や目印を置く。ワールド側で上書きする
func _decorate() -> void:
	pass


# ---------------------------------------------------------------- 地形
func _height_at_index(ix: int, iz: int) -> float:
	return _heights[iz * _grid_n + ix]


## ワールド座標 (x, z) の地面の高さ（生成後に使える）
func get_ground_height(x: float, z: float) -> float:
	var half := terrain_size * 0.5
	var fx := clampf((x + half) / terrain_cell, 0.0, _grid_n - 1.001)
	var fz := clampf((z + half) / terrain_cell, 0.0, _grid_n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _height_at_index(ix, iz)
	var h10 := _height_at_index(ix + 1, iz)
	var h01 := _height_at_index(ix, iz + 1)
	var h11 := _height_at_index(ix + 1, iz + 1)
	return lerpf(lerpf(h00, h10, tx), lerpf(h01, h11, tx), tz)


func _build_terrain() -> void:
	_grid_n = int(terrain_size / terrain_cell) + 1
	var half := terrain_size * 0.5
	_noise = FastNoiseLite.new()
	_noise.seed = terrain_seed
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = hill_frequency
	_noise.fractal_octaves = 3
	# 端の山並み用。稜線と谷ができるよう、地形本体より細かいノイズにする
	_rim_noise = FastNoiseLite.new()
	_rim_noise.seed = terrain_seed + 991
	_rim_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_rim_noise.frequency = 0.006
	_rim_noise.fractal_octaves = 2

	_heights.resize(_grid_n * _grid_n)
	for iz in _grid_n:
		for ix in _grid_n:
			var x := -half + ix * terrain_cell
			var z := -half + iz * terrain_cell
			_heights[iz * _grid_n + ix] = _terrain_height(x, z) + _rim_at(x, z)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iz in _grid_n:
		for ix in _grid_n:
			st.set_uv(Vector2(float(ix) / (_grid_n - 1), float(iz) / (_grid_n - 1)))
			st.add_vertex(Vector3(-half + ix * terrain_cell, _height_at_index(ix, iz), -half + iz * terrain_cell))
	for iz in _grid_n - 1:
		for ix in _grid_n - 1:
			var i00 := iz * _grid_n + ix
			var i10 := i00 + 1
			var i01 := i00 + _grid_n
			var i11 := i01 + 1
			# Godot の表面は時計回り。上から見て表になる並びにする（逆だと裏面カリングで地面が消える）
			st.add_index(i00); st.add_index(i10); st.add_index(i01)
			st.add_index(i10); st.add_index(i11); st.add_index(i01)
	st.generate_normals()
	terrain_mesh.mesh = st.commit()

	# 当たり判定（HeightMapShape3D は 1 マス = 1 単位なので cell 倍に拡大する）
	var shape := HeightMapShape3D.new()
	shape.map_width = _grid_n
	shape.map_depth = _grid_n
	shape.map_data = _heights
	terrain_shape.shape = shape
	terrain_shape.scale = Vector3(terrain_cell, 1.0, terrain_cell)


## 世界の端の盛り上がり。外側ほど急になり、slope_max_angle を超えたところで登れなくなる。
## 手前はなだらかな丘（近づける）、その先が崖のように立ち上がる形。フォグの中から山が現れる見え方になる
func _rim_at(x: float, z: float) -> float:
	if rim_height <= 0.0 or rim_width <= 0.0:
		return 0.0
	var half := terrain_size * 0.5
	var d := maxf(absf(x), absf(z))   # 四角い世界なので、中心からの「四角の距離」で測る
	var t := smoothstep(half - rim_width, half, d)
	# 稜線の高さを場所ごとに変えて、滑らかな器ではなく山並みに見せる
	var variation := 1.0 + rim_variation * _rim_noise.get_noise_2d(x, z)
	return rim_height * t * t * t * variation


# ---------------------------------------------------------------- 小物の共通ヘルパー
## 箱の静的物体を置く。layer 1 = 地形扱い（カメラも避ける）、4 = 小物（カメラはすり抜けて透過）
func add_static_box(parent: Node, pos: Vector3, size: Vector3, rot: Vector3, mat: Material, layer: int = 4) -> StaticBody3D:
	var box := BoxMesh.new()
	box.size = size
	var shape := BoxShape3D.new()
	shape.size = size
	return add_static_mesh(parent, pos, box, shape, rot, mat, layer)


func add_static_mesh(parent: Node, pos: Vector3, mesh: Mesh, shape: Shape3D, rot: Vector3, mat: Material, layer: int = 4) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.collision_layer = layer
	body.position = pos
	body.rotation = rot
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	body.add_child(mi)
	if shape:
		var cs := CollisionShape3D.new()
		cs.shape = shape
		body.add_child(cs)
	parent.add_child(body)
	return body


static func flat_material(color: Color, roughness: float = 0.95) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	return m
