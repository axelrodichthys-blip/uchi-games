extends WorldBase
## フェーズ1の「灰色の世界」（検証用）。起伏のある地面に目印の箱を撒く。
## 出現地点の右前には「急斜面テスト用」の山、左前には坂と崖の検証エリアを置く。
## 地形の共通部分（ノイズの丘・当たり判定・フォグ・F2 切替）は world_base.gd。

@export var landmark_count: int = 60
@export var landmark_spread: float = 120.0

@export_group("検証用の地形")
@export var steep_hill_position: Vector2 = Vector2(18.0, -14.0)  # 開始地点の右前
@export var steep_hill_radius: float = 10.0
@export var steep_hill_height: float = 17.0  # 半径10で高さ17 → 約60度（登れない）
@export var test_area_center: Vector2 = Vector2(-22.0, -18.0)  # 坂と崖の検証エリア（開始地点の左前）
@export var test_area_height: float = 7.0
@export var steps_origin: Vector2 = Vector2(6.0, 10.0)   # 階段と段差の検証（開始地点の右後ろ）

@onready var landmarks: Node3D = $Landmarks
@onready var test_area: Node3D = $TestArea

var _box_material: StandardMaterial3D


## 共通のノイズの丘に、急斜面の山と検証エリアの周りの平地を足す
func _terrain_height(x: float, z: float) -> float:
	var r := Vector2(x, z).length()
	var d := Vector2(x, z).distance_to(steep_hill_position)
	# 急斜面の山の周りはノイズを消して、斜面の角度をはっきりさせる
	var amp := smoothstep(flat_radius, flat_radius * 3.0, r) * hill_height
	amp *= smoothstep(steep_hill_radius, steep_hill_radius + 8.0, d)
	# 検証エリアの周りも平らにする
	amp *= smoothstep(22.0, 30.0, Vector2(x, z).distance_to(test_area_center))
	# 階段と段差の検証エリアの周りも平らにする
	amp *= smoothstep(18.0, 28.0, Vector2(x, z).distance_to(steps_origin + Vector2(10.0, 3.0)))
	var h := _noise.get_noise_2d(x, z) * amp
	h += steep_hill_height * clampf(1.0 - d / steep_hill_radius, 0.0, 1.0)
	return h


func _decorate() -> void:
	_box_material = WorldBase.flat_material(Color(0.42, 0.43, 0.46))
	_build_test_area()
	_build_steps()
	_spawn_landmarks()


## 階段（1 段 0.2m × 4）と、高さ違いの段（0.35 / 0.8 / 1.2 / 1.7m）。+Z 方向（開始地点の後ろ）へ並べる。
## 高さは身長 1.6m の膝（step_height 0.39）・肩（climb_height 1.3）を挟むように選んである
func _build_steps() -> void:
	var mat: Material = terrain_mesh.material_override
	var ox := steps_origin.x
	var oz := steps_origin.y
	for i in 4:
		var h := 0.2 * (i + 1)
		add_static_box(test_area, Vector3(ox, h * 0.5, oz + i * 1.0), Vector3(4.0, h, 1.0), Vector3.ZERO, mat, 1)
	add_static_box(test_area, Vector3(ox, 0.4, oz + 4.5), Vector3(4.0, 0.8, 2.0), Vector3.ZERO, mat, 1)   # 階段の踊り場
	var heights := [0.35, 0.8, 1.2, 1.7]
	for i in heights.size():
		var h: float = heights[i]
		add_static_box(test_area, Vector3(ox + 6.0 + i * 5.0, h * 0.5, oz + 2.0), Vector3(3.0, h, 3.0), Vector3.ZERO, mat, 1)


# ---------------------------------------------------------------- 検証エリア
## 高さ test_area_height の台地。開始地点側（+Z）に 30度の登り坂、-X 側に 42度の登り坂、
## -Z 側に 50度の下り坂（登れない）、+X 側は崖（そのまま落ちる）。
func _build_test_area() -> void:
	var c := Vector3(test_area_center.x, 0.0, test_area_center.y)
	var h := test_area_height
	var mat: Material = terrain_mesh.material_override
	var size := Vector3(16.0, h, 14.0)
	add_static_box(test_area, c + Vector3(0, h * 0.5, 0), size, Vector3.ZERO, mat, 1)
	# 坂: (面までの距離, 角度, 方向) 方向は台地の中心から見た向き
	var ramps := [
		[size.z * 0.5, 30.0, Vector3(0, 0, 1)],    # +Z（開始地点側）30度
		[size.x * 0.5, 42.0, Vector3(-1, 0, 0)],   # -X 42度（登れる限界の少し手前）
		[size.z * 0.5, 50.0, Vector3(0, 0, -1)],   # -Z 50度（登れない = 急な下り坂）
	]
	var thickness := 1.0
	for ramp in ramps:
		var face_dist: float = ramp[0]
		var angle_deg: float = ramp[1]
		var dir: Vector3 = ramp[2]
		var a := deg_to_rad(angle_deg)
		# 坂の上面: 台地の縁の少し内側・少し上（A）から、地面の少し下（B）まで。
		# 上端を台地より高くするのは、カプセルが数 cm の段差でも「壁」と判定して止まるため。
		var top_lift := 0.22
		var bury := 0.3
		var A := c + dir * (face_dist - 0.3) + Vector3(0, h + top_lift, 0)
		var B := c + dir * (face_dist + (h + top_lift + bury) / tan(a)) + Vector3(0, -bury, 0)
		var n := Vector3(0, cos(a), 0) + dir * sin(a)   # 上面の法線
		var length := (A - B).length()
		var center := (A + B) * 0.5 - n * (thickness * 0.5)
		var box_size: Vector3
		var rot: Vector3
		if dir.z != 0.0:
			box_size = Vector3(6.0, thickness, length)
			rot = Vector3(a * dir.z, 0, 0)
		else:
			box_size = Vector3(length, thickness, 6.0)
			rot = Vector3(0, 0, -a * dir.x)
		add_static_box(test_area, center, box_size, rot, mat, 1)


# ---------------------------------------------------------------- 目印
func _spawn_landmarks() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = terrain_seed
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
		if Vector2(x, z).distance_to(test_area_center) < 26.0:
			x -= 30.0
		var pos := Vector3(x, get_ground_height(x, z) + size.y * 0.5 - 0.5, z)
		add_static_box(landmarks, pos, size, Vector3(0, rng.randf_range(0.0, TAU), 0), _box_material)

	# 遠くに「行ってみたくなる」大きな柱を1本
	var px := 0.0
	var pz := -160.0
	add_static_box(landmarks, Vector3(px, get_ground_height(px, pz) + 20.0 - 1.0, pz), Vector3(6.0, 40.0, 6.0), Vector3.ZERO, _box_material)
