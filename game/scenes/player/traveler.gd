extends Node3D
## 仮キャラ「旅人」。プリミティブ（カプセル・球・箱）で人型を組み立て、
## 待機 / 歩き / 走り / ジャンプ / 着地 を手続き的に動かす（Mixamo 導入までのつなぎ）。
## 色: 身体は黒、帽子とコートはサンドベージュ。コートは前が割れた長いコート。
##
## player.gd から毎物理フレーム update_motion() を呼んで状態を渡す。

const BODY_COLOR := Color(0.07, 0.07, 0.08)
const CLOTH_COLOR := Color(0.83, 0.74, 0.58)   # サンドベージュ
const EYE_COLOR := Color(1, 1, 1)

# 寸法（m）。身長 約1.6m（4.5頭身）
const HIP_HEIGHT := 0.80
const TORSO_LENGTH := 0.50
const HEAD_RADIUS := 0.17
const UPPER_LEG := 0.40
const LOWER_LEG := 0.40
const UPPER_ARM := 0.30
const LOWER_ARM := 0.28
const SHOULDER_WIDTH := 0.20
const HIP_WIDTH := 0.11
const COAT_LENGTH := 0.72   # 腰から裾まで（膝下まで）

# ---- 部位（ピボットノード） ----
var _root_offset: Node3D      # 上下の揺れ・着地の沈み込み
var _hips: Node3D
var _torso: Node3D
var _head: Node3D
var _upper_leg: Array[Node3D] = []
var _lower_leg: Array[Node3D] = []
var _upper_arm: Array[Node3D] = []
var _lower_arm: Array[Node3D] = []
var _coat_flap: Array[Node3D] = []

var _body_mat: StandardMaterial3D
var _cloth_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D

# ---- 動きの状態 ----
var _phase: float = 0.0        # 歩行サイクルの位相（ラジアン）
var _walk_blend: float = 0.0   # 0=待機 1=歩き
var _run_blend: float = 0.0    # 0=歩き 1=走り
var _air_blend: float = 0.0    # 0=接地 1=空中
var _land_squash: float = 0.0  # 着地の沈み込み
var _was_on_floor: bool = true
var _idle_time: float = 0.0
var _speed_smooth: float = 0.0


func _ready() -> void:
	_build()


# ---------------------------------------------------------------- 組み立て
func _build() -> void:
	_body_mat = _make_material(BODY_COLOR)
	_cloth_mat = _make_material(CLOTH_COLOR)
	_eye_mat = _make_material(EYE_COLOR)
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_root_offset = _pivot(self, "RootOffset", Vector3.ZERO)
	_hips = _pivot(_root_offset, "Hips", Vector3(0, HIP_HEIGHT, 0))

	# 胴（コートの上半身 = ベージュ）
	_torso = _pivot(_hips, "Torso", Vector3.ZERO)
	_capsule(_torso, "TorsoMesh", 0.17, TORSO_LENGTH + 0.2, Vector3(0, TORSO_LENGTH * 0.5, 0), _cloth_mat)
	# 襟（黒い首元）
	_sphere(_torso, "Neck", 0.09, Vector3(0, TORSO_LENGTH + 0.02, 0), _body_mat)

	# 頭・目・帽子
	_head = _pivot(_torso, "Head", Vector3(0, TORSO_LENGTH + 0.10, 0))
	_sphere(_head, "HeadMesh", HEAD_RADIUS, Vector3(0, HEAD_RADIUS, 0), _body_mat)
	_sphere(_head, "EyeL", 0.03, Vector3(-0.06, HEAD_RADIUS + 0.02, -HEAD_RADIUS + 0.02), _eye_mat)
	_sphere(_head, "EyeR", 0.03, Vector3(0.06, HEAD_RADIUS + 0.02, -HEAD_RADIUS + 0.02), _eye_mat)
	var brim := _cylinder(_head, "HatBrim", 0.30, 0.30, 0.03, Vector3(0, HEAD_RADIUS * 1.7, 0), _cloth_mat)
	brim.rotation.x = deg_to_rad(4.0)
	var cone := _cylinder(_head, "HatCone", 0.0, 0.19, 0.55, Vector3(0, HEAD_RADIUS * 1.7 + 0.27, 0), _cloth_mat)
	cone.rotation.z = deg_to_rad(-8.0)   # 少し折れた帽子
	cone.rotation.x = deg_to_rad(6.0)

	# 腕（肩がピボット）。袖はベージュ、手は黒
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var shoulder := _pivot(_torso, "UpperArm%d" % side, Vector3(sx * SHOULDER_WIDTH, TORSO_LENGTH - 0.04, 0))
		_capsule(shoulder, "UpperArmMesh", 0.06, UPPER_ARM + 0.1, Vector3(0, -UPPER_ARM * 0.5, 0), _cloth_mat)
		var elbow := _pivot(shoulder, "LowerArm", Vector3(0, -UPPER_ARM, 0))
		_capsule(elbow, "LowerArmMesh", 0.055, LOWER_ARM + 0.08, Vector3(0, -LOWER_ARM * 0.5, 0), _cloth_mat)
		_sphere(elbow, "Hand", 0.06, Vector3(0, -LOWER_ARM - 0.03, 0), _body_mat)
		_upper_arm.append(shoulder)
		_lower_arm.append(elbow)

	# 脚（股関節がピボット）。黒
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var hip := _pivot(_hips, "UpperLeg%d" % side, Vector3(sx * HIP_WIDTH, 0, 0))
		_capsule(hip, "UpperLegMesh", 0.075, UPPER_LEG + 0.12, Vector3(0, -UPPER_LEG * 0.5, 0), _body_mat)
		var knee := _pivot(hip, "LowerLeg", Vector3(0, -UPPER_LEG, 0))
		_capsule(knee, "LowerLegMesh", 0.065, LOWER_LEG + 0.08, Vector3(0, -LOWER_LEG * 0.5, 0), _body_mat)
		_box(knee, "Foot", Vector3(0.12, 0.08, 0.24), Vector3(0, -LOWER_LEG - 0.02, -0.05), _body_mat)
		_upper_leg.append(hip)
		_lower_leg.append(knee)

	# コートの裾（左右2枚、前が割れている）。腰がピボット
	for side in 2:
		var flap := _pivot(_hips, "CoatFlap%d" % side, Vector3(0, 0.02, 0))
		var mesh := MeshInstance3D.new()
		mesh.name = "CoatMesh"
		mesh.mesh = _make_coat_half_mesh(side == 0)
		mesh.material_override = _cloth_mat
		flap.add_child(mesh)
		_coat_flap.append(flap)


func _make_material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.9
	return m


func _pivot(parent: Node3D, pivot_name: String, pos: Vector3) -> Node3D:
	var n := Node3D.new()
	n.name = pivot_name
	n.position = pos
	parent.add_child(n)
	return n


func _mesh_instance(parent: Node3D, mesh_name: String, mesh: Mesh, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = mesh_name
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


func _capsule(parent: Node3D, mesh_name: String, radius: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := CapsuleMesh.new()
	m.radius = radius
	m.height = height
	m.radial_segments = 12
	m.rings = 4
	return _mesh_instance(parent, mesh_name, m, pos, mat)


func _sphere(parent: Node3D, mesh_name: String, radius: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := SphereMesh.new()
	m.radius = radius
	m.height = radius * 2.0
	m.radial_segments = 16
	m.rings = 8
	return _mesh_instance(parent, mesh_name, m, pos, mat)


func _cylinder(parent: Node3D, mesh_name: String, top_r: float, bottom_r: float, height: float, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := CylinderMesh.new()
	m.top_radius = top_r
	m.bottom_radius = bottom_r
	m.height = height
	m.radial_segments = 16
	return _mesh_instance(parent, mesh_name, m, pos, mat)


func _box(parent: Node3D, mesh_name: String, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var m := BoxMesh.new()
	m.size = size
	return _mesh_instance(parent, mesh_name, m, pos, mat)


## コートの裾の片側。腰の周りを後ろ中心に約150度覆う円錐台の帯。前（-Z側）が開く。
func _make_coat_half_mesh(left: bool) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 8
	var top_r := 0.20
	var bottom_r := 0.36
	# 角度: 後ろ(+Z)が 90度。左側は 90→ 215 度、右側は 90 → -35 度（前の割れ目を 70 度空ける）
	var a0 := deg_to_rad(90.0)
	var a1 := deg_to_rad(215.0) if left else deg_to_rad(-35.0)
	var verts_top: Array[Vector3] = []
	var verts_bottom: Array[Vector3] = []
	for i in segments + 1:
		var a := lerpf(a0, a1, float(i) / segments)
		verts_top.append(Vector3(cos(a) * top_r, 0.0, sin(a) * top_r))
		verts_bottom.append(Vector3(cos(a) * bottom_r, -COAT_LENGTH, sin(a) * bottom_r))
	for i in segments:
		var t0 := verts_top[i]
		var t1 := verts_top[i + 1]
		var b0 := verts_bottom[i]
		var b1 := verts_bottom[i + 1]
		# 両面描画にしたいので表裏2枚
		for flip in 2:
			if flip == 0:
				st.add_vertex(t0); st.add_vertex(b0); st.add_vertex(t1)
				st.add_vertex(t1); st.add_vertex(b0); st.add_vertex(b1)
			else:
				st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b0)
				st.add_vertex(t1); st.add_vertex(b1); st.add_vertex(b0)
	st.generate_normals()
	return st.commit()


# ---------------------------------------------------------------- 動き
## speed: 水平速度 m/s, on_floor: 接地, vertical_velocity: 上下速度
func update_motion(speed: float, on_floor: bool, vertical_velocity: float, delta: float) -> void:
	_speed_smooth = lerpf(_speed_smooth, speed, clampf(10.0 * delta, 0.0, 1.0))

	var walk_speed: float = Tuning.walk_speed
	var run_speed: float = Tuning.run_speed
	var target_walk := clampf(_speed_smooth / maxf(walk_speed * 0.6, 0.1), 0.0, 1.0)
	var target_run := clampf((_speed_smooth - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	_walk_blend = lerpf(_walk_blend, target_walk, clampf(8.0 * delta, 0.0, 1.0))
	_run_blend = lerpf(_run_blend, target_run, clampf(6.0 * delta, 0.0, 1.0))
	_air_blend = lerpf(_air_blend, 0.0 if on_floor else 1.0, clampf(12.0 * delta, 0.0, 1.0))

	# 着地の沈み込み
	if on_floor and not _was_on_floor:
		_land_squash = clampf(absf(vertical_velocity) / 8.0, 0.2, 1.0)
	_was_on_floor = on_floor
	_land_squash = move_toward(_land_squash, 0.0, 3.0 * delta)

	# 歩行サイクル: 1歩の長さ（歩き 0.7m、走り 1.0m）で位相を進める
	var stride := lerpf(0.70, 1.00, _run_blend)
	if on_floor:
		_phase += (_speed_smooth / stride) * PI * delta
	_idle_time += delta

	_apply_pose(delta)


func _apply_pose(delta: float) -> void:
	var s := sin(_phase)
	var c := cos(_phase)
	var move := _walk_blend * (1.0 - _air_blend)
	var run := _run_blend

	# 振り幅（度）
	var leg_amp := lerpf(28.0, 45.0, run) * move
	var knee_amp := lerpf(35.0, 70.0, run) * move
	var arm_amp := lerpf(18.0, 50.0, run) * move
	var elbow_bend := lerpf(10.0, 75.0, run) * move + 8.0
	var lean := lerpf(0.0, 12.0, run) * move

	# 待機: 呼吸と小さな揺れ
	var breath := sin(_idle_time * TAU * 0.25) * (1.0 - move)
	var sway := sin(_idle_time * TAU * 0.13) * (1.0 - move)

	# 脚: 左右逆位相。膝は脚が後ろ→前へ振れるとき曲がる
	for side in 2:
		var sign_ := 1.0 if side == 0 else -1.0
		var swing := s * sign_
		var upper := swing * leg_amp
		var knee := maxf(0.0, -c * sign_) * knee_amp
		# 空中: 前脚を上げ、後脚を後ろに（ジャンプの形）
		upper = lerpf(upper, 35.0 * sign_ - 10.0, _air_blend)
		knee = lerpf(knee, 40.0 if side == 0 else 15.0, _air_blend)
		# 着地: 膝を曲げる
		knee += _land_squash * 25.0
		upper -= _land_squash * 10.0
		_set_rot(_upper_leg[side], Vector3(deg_to_rad(-upper), 0, 0), delta)
		_set_rot(_lower_leg[side], Vector3(deg_to_rad(knee), 0, 0), delta)

	# 腕: 脚と逆位相。肘は走るほど曲がる。待機ではわずかに揺れる
	for side in 2:
		var sign_ := -1.0 if side == 0 else 1.0
		var swing := s * sign_
		var upper := swing * arm_amp + sway * 3.0
		var out := 8.0 + run * 6.0 * move   # 腕を少し外に開く
		upper = lerpf(upper, -40.0, _air_blend)  # 空中では腕を前上に
		var elbow := elbow_bend + maxf(0.0, swing) * 15.0 * move
		elbow = lerpf(elbow, 60.0, _air_blend)
		var sx := -1.0 if side == 0 else 1.0
		_set_rot(_upper_arm[side], Vector3(deg_to_rad(upper), 0, deg_to_rad(sx * -out)), delta)
		_set_rot(_lower_arm[side], Vector3(deg_to_rad(-elbow), 0, 0), delta)

	# コートの裾: 脚の振りに少し遅れて追従、走ると後ろに流れる
	for side in 2:
		var sign_ := 1.0 if side == 0 else -1.0
		var flap := s * sign_ * leg_amp * 0.35
		flap = lerpf(flap, 25.0, _air_blend)   # 空中ではふわっと開く
		var back := run * move * 12.0
		var sx := -1.0 if side == 0 else 1.0
		_set_rot(_coat_flap[side], Vector3(deg_to_rad(-flap + back), 0, deg_to_rad(sx * (6.0 + run * move * 10.0))), delta * 0.7)

	# 胴: 前傾と左右のひねり、呼吸
	_set_rot(_torso, Vector3(deg_to_rad(-lean - breath * 1.5), deg_to_rad(s * 4.0 * move), deg_to_rad(sway * 1.5)), delta)
	_torso.scale = Vector3(1, 1 + breath * 0.012, 1)
	_set_rot(_head, Vector3(deg_to_rad(lean * 0.5 + breath * 1.0), deg_to_rad(-s * 3.0 * move), 0), delta)

	# 上下の揺れ（1歩ごとに2回）、着地の沈み込み、空中はやや持ち上げ
	var bob := absf(s) * lerpf(0.025, 0.06, run) * move
	var y := bob - _land_squash * 0.10 + _air_blend * 0.02
	_root_offset.position.y = lerpf(_root_offset.position.y, y, clampf(15.0 * delta, 0.0, 1.0))


func _set_rot(node: Node3D, target: Vector3, delta: float) -> void:
	var t := clampf(18.0 * delta, 0.0, 1.0)
	node.rotation = node.rotation.lerp(target, t)
