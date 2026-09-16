class_name WorldBase
extends Node3D
## すべてのワールドの土台。新しいワールドはこれを継承して作る（手順は scenes/worlds/README.md）。
##
## やること:
##   - ノイズで起伏のある地面を作る（出現地点の周り flat_radius は平ら）。高さの式は _terrain_height() で差し替えられる
##   - フォグの濃さを Tuning から毎フレーム反映する（F1 で変えられる）。ワールドごとの初期値は fog_density_default
##   - F2 で次のワールドへ（WorldList）
##   - 小物を置くときの共通ヘルパー（add_static_box / add_static_mesh）
##
## 必要なノード（シーン側で用意する）:
##   WorldEnvironment, DirectionalLight3D, Terrain(StaticBody3D, layer 1) / MeshInstance3D / CollisionShape3D,
##   Player（scenes/player/player.tscn）, HUD, DebugPanel

@export_multiline var hud_hint: String = ""   # HUD の操作案内の末尾に足す、このワールド固有の一言

@export_group("地形")
@export var terrain_size: float = 600.0   # 一辺 m
@export var terrain_cell: float = 3.0     # 頂点の間隔 m
@export var hill_height: float = 10.0     # 丘の高さの目安 m
@export var hill_frequency: float = 0.012 # 小さいほどなだらかで大きな丘
@export var flat_radius: float = 15.0     # この半径までは平ら
@export var terrain_seed: int = 7

@export_group("風景")
@export var fog_density_default: float = 0.012

@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var terrain_mesh: MeshInstance3D = $Terrain/MeshInstance3D
@onready var terrain_shape: CollisionShape3D = $Terrain/CollisionShape3D
@onready var player: CharacterBody3D = $Player

var _heights: PackedFloat32Array
var _grid_n: int = 0
var _noise: FastNoiseLite


func _ready() -> void:
	Tuning.fog_density = fog_density_default
	_build_terrain()
	_decorate()


func _process(_delta: float) -> void:
	var env := environment.environment
	if env and not is_equal_approx(env.fog_density, Tuning.fog_density):
		env.fog_density = Tuning.fog_density


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("next_world"):
		get_viewport().set_input_as_handled()
		get_tree().change_scene_to_file.call_deferred(WorldList.next_scene(scene_file_path))


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

	_heights.resize(_grid_n * _grid_n)
	for iz in _grid_n:
		for ix in _grid_n:
			_heights[iz * _grid_n + ix] = _terrain_height(-half + ix * terrain_cell, -half + iz * terrain_cell)

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
