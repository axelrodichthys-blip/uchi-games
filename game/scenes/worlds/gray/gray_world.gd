extends Node3D
## フェーズ1の「灰色の世界」。平らな地面に目印の箱を撒く。
## フォグの濃さは Tuning から毎フレーム反映する（デバッグパネルで変えられるように）。

@export var landmark_count: int = 60
@export var landmark_spread: float = 120.0
@export var landmark_seed: int = 7

@onready var environment: WorldEnvironment = $WorldEnvironment
@onready var landmarks: Node3D = $Landmarks

var _box_material: StandardMaterial3D


func _ready() -> void:
	_box_material = StandardMaterial3D.new()
	_box_material.albedo_color = Color(0.58, 0.59, 0.62)
	_box_material.roughness = 0.95
	_spawn_landmarks()


func _process(_delta: float) -> void:
	var env := environment.environment
	if env and not is_equal_approx(env.fog_density, Tuning.fog_density):
		env.fog_density = Tuning.fog_density


func _spawn_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = landmark_seed
	for i in landmark_count:
		var size := Vector3(
			rng.randf_range(0.8, 4.0),
			rng.randf_range(1.0, 12.0),
			rng.randf_range(0.8, 4.0)
		)
		var pos := Vector3(
			rng.randf_range(-landmark_spread, landmark_spread),
			size.y * 0.5,
			rng.randf_range(-landmark_spread, landmark_spread)
		)
		# 出現位置の近くには置かない
		if Vector2(pos.x, pos.z).length() < 6.0:
			pos.x += 8.0
		_add_box(pos, size, rng.randf_range(0.0, TAU))

	# 遠くに「行ってみたくなる」大きな柱を1本
	_add_box(Vector3(0.0, 20.0, -160.0), Vector3(6.0, 40.0, 6.0), 0.0)


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
