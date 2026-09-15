extends Node3D
## フェーズ1の「灰色の世界」。起伏のある地面に目印の箱を撒く。
## 地形はノイズで生成する。出現地点の周り（半径 flat_radius）は平ら、外側ほど丘になる。
## 出現地点の東（+X）には「急斜面テスト用」の山を置く（slope_max_angle より急なので滑り落ちる）。
## フォグの濃さは Tuning から毎フレーム反映する（デバッグパネルで変えられるように）。

@export var landmark_count: int = 60
@export var landmark_spread: float = 120.0
@export var landmark_seed: int = 7

@export_group("地形")
@export var terrain_size: float = 600.0   # 一辺 m
@export var terrain_cell: float = 3.0     # 頂点の間隔 m
@export var hill_height: float = 10.0     # 丘の高さの目安 m
@export var hill_frequency: float = 0.012 # 小さいほどなだらかで大きな丘
@export var flat_radius: float = 15.0     # この半径までは平ら
@export var steep_hill_position: Vector2 = Vector2(40.0, 0.0)
@export var steep_hill_radius: float = 12.0
@export var steep_hill_height: float = 14.0  # 半径12で高さ14 → 約50度（登れない）

@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var landmarks: Node3D = $Landmarks
@onready var terrain_mesh: MeshInstance3D = $Terrain/MeshInstance3D
@onready var terrain_shape: CollisionShape3D = $Terrain/CollisionShape3D

var _box_material: StandardMaterial3D
var _heights: PackedFloat32Array
var _grid_n: int = 0


func _ready() -> void:
	_box_material = StandardMaterial3D.new()
	_box_material.albedo_color = Color(0.42, 0.43, 0.46)
	_box_material.roughness = 0.95
	_build_terrain()
	_spawn_landmarks()


func _process(_delta: float) -> void:
	var env := environment.environment
	if env and not is_equal_approx(env.fog_density, Tuning.fog_density):
		env.fog_density = Tuning.fog_density


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
	var noise := FastNoiseLite.new()
	noise.seed = landmark_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = hill_frequency
	noise.fractal_octaves = 3

	_heights.resize(_grid_n * _grid_n)
	for iz in _grid_n:
		for ix in _grid_n:
			var x := -half + ix * terrain_cell
			var z := -half + iz * terrain_cell
			var r := Vector2(x, z).length()
			var amp := smoothstep(flat_radius, flat_radius * 3.0, r) * hill_height
			var h := noise.get_noise_2d(x, z) * amp
			var d := Vector2(x, z).distance_to(steep_hill_position)
			h += steep_hill_height * clampf(1.0 - d / steep_hill_radius, 0.0, 1.0)
			_heights[iz * _grid_n + ix] = h

	# メッシュ
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
			st.add_index(i00); st.add_index(i01); st.add_index(i10)
			st.add_index(i10); st.add_index(i01); st.add_index(i11)
	st.generate_normals()
	terrain_mesh.mesh = st.commit()

	# 当たり判定（HeightMapShape3D は 1 マス = 1 単位なので cell 倍に拡大する）
	var shape := HeightMapShape3D.new()
	shape.map_width = _grid_n
	shape.map_depth = _grid_n
	shape.map_data = _heights
	terrain_shape.shape = shape
	terrain_shape.scale = Vector3(terrain_cell, 1.0, terrain_cell)


# ---------------------------------------------------------------- 目印
func _spawn_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = landmark_seed
	for i in landmark_count:
		var size := Vector3(
			rng.randf_range(0.8, 4.0),
			rng.randf_range(1.0, 12.0),
			rng.randf_range(0.8, 4.0)
		)
		var x := rng.randf_range(-landmark_spread, landmark_spread)
		var z := rng.randf_range(-landmark_spread, landmark_spread)
		# 出現位置と急斜面の山の近くには置かない
		if Vector2(x, z).length() < 6.0:
			x += 8.0
		if Vector2(x, z).distance_to(steep_hill_position) < steep_hill_radius + 3.0:
			z += steep_hill_radius + 6.0
		var pos := Vector3(x, get_ground_height(x, z) + size.y * 0.5 - 0.5, z)
		_add_box(pos, size, rng.randf_range(0.0, TAU))

	# 遠くに「行ってみたくなる」大きな柱を1本
	var px := 0.0
	var pz := -160.0
	_add_box(Vector3(px, get_ground_height(px, pz) + 20.0 - 1.0, pz), Vector3(6.0, 40.0, 6.0), 0.0)


func _add_box(pos: Vector3, size: Vector3, yaw: float) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.position = pos
	body.rotation.y = yaw

	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = _box_material
	body.add_child(mesh)

	var shape := CollisionShape3D.new()
	var box_shape := BoxShape3D.new()
	box_shape.size = size
	shape.shape = box_shape
	body.add_child(shape)

	landmarks.add_child(body)
