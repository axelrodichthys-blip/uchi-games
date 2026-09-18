extends Node3D
## 仮キャラ「旅人」。人体と同じ関節構成で組み立て、歩行を生体力学に沿って手続き的に動かす。
## Mixamo（モーションキャプチャ由来）の本アニメが入るまでのつなぎ。
##
## 関節（Mixamo / 人型リグと同じ並び）:
##   Hips（骨盤）> Spine > Chest > Neck > Head
##                        Chest > Clavicle > Shoulder（上腕）> Elbow（前腕）> Wrist（手）
##   Hips > Hip（大腿）> Knee（下腿）> Ankle（足）> Toe
##
## 歩行の作り:
##   - 足は「接地中は地面に固定され、体の速さで後ろへ流れる」→ 足が滑らない
##   - 足の位置から股・膝の角度を逆運動学（2本骨IK）で解く
##   - 骨盤は歩幅に合わせて上下・左右・ひねり・傾き、胸は骨盤と逆にひねる、頭は前を向き続ける
##   - 腕は脚と逆位相、肘は前に曲がる。走ると前傾し、肘が深く曲がる
##
## player.gd から毎物理フレーム update_motion() を呼んで状態を渡す。

const BODY_COLOR := Color(0.07, 0.07, 0.08)
const CLOTH_COLOR := Color(0.83, 0.74, 0.58)   # サンドベージュ
const EYE_COLOR := Color(1, 1, 1)

# ---- 基準寸法（m）。Tuning の体型倍率で拡縮する ----
const ANKLE_H := 0.08
const SHIN := 0.40
const THIGH := 0.42
const HIP_W := 0.10          # 股関節の左右オフセット
const SPINE_L := 0.10
const CHEST_L := 0.16
const NECK_L := 0.12
const HEAD_R := 0.15
const SHOULDER_W := 0.19
const UPPER_ARM := 0.28
const FORE_ARM := 0.26
const COAT_LENGTH := 0.62

# ---- 関節ノード ----
var _root: Node3D
var _hips: Node3D
var _spine: Node3D
var _chest: Node3D
var _neck: Node3D
var _head: Node3D
var _clavicle: Array[Node3D] = []
var _shoulder: Array[Node3D] = []
var _elbow: Array[Node3D] = []
var _wrist: Array[Node3D] = []
var _hip: Array[Node3D] = []
var _knee: Array[Node3D] = []
var _ankle: Array[Node3D] = []
var _coat: Array[Node3D] = []
var _chest_mesh: MeshInstance3D

var _body_mat: StandardMaterial3D
var _cloth_mat: StandardMaterial3D
var _eye_mat: StandardMaterial3D

# 実寸（倍率適用後）
var _thigh := THIGH
var _shin := SHIN
var _ankle_h := ANKLE_H
var _hip_w := HIP_W
var _shape_key := ""

# ---- 動きの状態 ----
var _cycle: float = 0.0        # 歩行サイクル（1.0 で左右1歩ずつ）
var _move: float = 0.0         # 0=待機 1=歩き以上
var _run: float = 0.0          # 0=歩き 1=走り
var _air: float = 0.0          # 0=接地 1=空中
var _squash: float = 0.0       # 着地の沈み込み
var _was_on_floor: bool = true
var _time: float = 0.0
var _speed_s: float = 0.0
var _yaw_rate_s: float = 0.0
var _hips_y: float = 0.0


func _ready() -> void:
	_build()


# ================================================================ 組み立て
func _shape_signature() -> String:
	return "%.3f/%.3f/%.3f/%.3f/%.3f" % [Tuning.body_scale, Tuning.leg_length, Tuning.arm_length, Tuning.head_size, Tuning.hat_size]


func _build() -> void:
	for child in get_children():
		child.queue_free()
	_clavicle.clear(); _shoulder.clear(); _elbow.clear(); _wrist.clear()
	_hip.clear(); _knee.clear(); _ankle.clear(); _coat.clear()
	_shape_key = _shape_signature()

	var S: float = Tuning.body_scale
	var LEG: float = Tuning.leg_length
	var ARM: float = Tuning.arm_length
	var HEAD: float = Tuning.head_size
	var HAT: float = Tuning.hat_size
	_thigh = THIGH * S * LEG
	_shin = SHIN * S * LEG
	_ankle_h = ANKLE_H * S
	_hip_w = HIP_W * S
	_hips_y = _thigh + _shin + _ankle_h - 0.02

	_body_mat = _make_material(BODY_COLOR)
	_cloth_mat = _make_material(CLOTH_COLOR)
	_eye_mat = _make_material(EYE_COLOR)
	_eye_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_root = _pivot(self, "Root", Vector3.ZERO)
	_hips = _pivot(_root, "Hips", Vector3(0, _hips_y, 0))
	# 骨盤の肉
	_capsule(_hips, "PelvisMesh", 0.15 * S, 0.30 * S, Vector3(0, 0.02 * S, 0), _cloth_mat)

	# 背骨・胸・首・頭
	_spine = _pivot(_hips, "Spine", Vector3(0, SPINE_L * S, 0))
	_capsule(_spine, "SpineMesh", 0.145 * S, 0.30 * S, Vector3(0, 0.06 * S, 0), _cloth_mat)
	_chest = _pivot(_spine, "Chest", Vector3(0, CHEST_L * S, 0))
	_chest_mesh = _capsule(_chest, "ChestMesh", 0.16 * S, 0.30 * S, Vector3(0, 0.04 * S, 0), _cloth_mat)
	_sphere(_chest, "Collar", 0.075 * S, Vector3(0, NECK_L * S * 0.6, 0), _body_mat)
	_neck = _pivot(_chest, "Neck", Vector3(0, NECK_L * S, 0))
	_head = _pivot(_neck, "Head", Vector3(0, 0.05 * S, 0))
	var hr := HEAD_R * S * HEAD
	_sphere(_head, "HeadMesh", hr, Vector3(0, hr, 0), _body_mat)
	_sphere(_head, "EyeL", 0.028 * S * HEAD, Vector3(-0.055 * S * HEAD, hr + 0.02 * S, -hr + 0.02 * S), _eye_mat)
	_sphere(_head, "EyeR", 0.028 * S * HEAD, Vector3(0.055 * S * HEAD, hr + 0.02 * S, -hr + 0.02 * S), _eye_mat)
	var brim := _cylinder(_head, "HatBrim", 0.30 * S * HAT, 0.30 * S * HAT, 0.025 * S, Vector3(0, hr * 1.65, 0), _cloth_mat)
	brim.rotation.x = deg_to_rad(4.0)
	var cone := _cylinder(_head, "HatCone", 0.0, 0.18 * S * HAT, 0.52 * S * HAT, Vector3(0, hr * 1.65 + 0.26 * S * HAT, 0), _cloth_mat)
	cone.rotation.z = deg_to_rad(-9.0)
	cone.rotation.x = deg_to_rad(6.0)

	# 腕: 鎖骨 > 肩 > 肘 > 手首
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var clav := _pivot(_chest, "Clavicle%d" % side, Vector3(sx * 0.05 * S, 0.10 * S, 0))
		var sh := _pivot(clav, "Shoulder", Vector3(sx * (SHOULDER_W - 0.05) * S, 0, 0))
		_sphere(sh, "ShoulderMesh", 0.075 * S, Vector3.ZERO, _cloth_mat)
		var ua := UPPER_ARM * S * ARM
		var fa := FORE_ARM * S * ARM
		_capsule(sh, "UpperArmMesh", 0.058 * S, ua + 0.06 * S, Vector3(0, -ua * 0.5, 0), _cloth_mat)
		var el := _pivot(sh, "Elbow", Vector3(0, -ua, 0))
		_capsule(el, "ForeArmMesh", 0.052 * S, fa + 0.04 * S, Vector3(0, -fa * 0.5, 0), _cloth_mat)
		var wr := _pivot(el, "Wrist", Vector3(0, -fa, 0))
		_sphere(wr, "Hand", 0.055 * S, Vector3(0, -0.03 * S, 0), _body_mat)
		_clavicle.append(clav); _shoulder.append(sh); _elbow.append(el); _wrist.append(wr)

	# 脚: 股 > 膝 > 足首 > つま先
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var hip := _pivot(_hips, "Hip%d" % side, Vector3(sx * _hip_w, 0, 0))
		_capsule(hip, "ThighMesh", 0.075 * S, _thigh + 0.10 * S, Vector3(0, -_thigh * 0.5, 0), _body_mat)
		var knee := _pivot(hip, "Knee", Vector3(0, -_thigh, 0))
		_capsule(knee, "ShinMesh", 0.062 * S, _shin + 0.06 * S, Vector3(0, -_shin * 0.5, 0), _body_mat)
		var ankle := _pivot(knee, "Ankle", Vector3(0, -_shin, 0))
		_box(ankle, "FootMesh", Vector3(0.10 * S, _ankle_h, 0.22 * S), Vector3(0, -_ankle_h * 0.5, -0.05 * S), _body_mat)
		_box(ankle, "ToeMesh", Vector3(0.09 * S, _ankle_h * 0.7, 0.06 * S), Vector3(0, -_ankle_h * 0.65, -0.18 * S), _body_mat)
		_hip.append(hip); _knee.append(knee); _ankle.append(ankle)

	# コートの裾（左右2枚、前が割れている）
	for side in 2:
		var flap := _pivot(_hips, "Coat%d" % side, Vector3(0, 0.0, 0))
		var mesh := MeshInstance3D.new()
		mesh.name = "CoatMesh"
		mesh.mesh = _make_coat_half_mesh(side == 0, S)
		mesh.material_override = _cloth_mat
		flap.add_child(mesh)
		_coat.append(flap)


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
	m.height = maxf(height, radius * 2.0 + 0.01)
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


## コートの裾の片側。腰の周りを後ろ中心に覆う円錐台の帯。前（-Z側）が開く。
func _make_coat_half_mesh(left: bool, S: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 8
	var top_r := 0.19 * S
	var bottom_r := 0.34 * S
	var a0 := deg_to_rad(90.0)
	var a1 := deg_to_rad(215.0) if left else deg_to_rad(-35.0)
	var verts_top: Array[Vector3] = []
	var verts_bottom: Array[Vector3] = []
	for i in segments + 1:
		var a := lerpf(a0, a1, float(i) / segments)
		verts_top.append(Vector3(cos(a) * top_r, 0.0, sin(a) * top_r))
		verts_bottom.append(Vector3(cos(a) * bottom_r, -COAT_LENGTH * S, sin(a) * bottom_r))
	for i in segments:
		var t0 := verts_top[i]
		var t1 := verts_top[i + 1]
		var b0 := verts_bottom[i]
		var b1 := verts_bottom[i + 1]
		st.add_vertex(t0); st.add_vertex(b0); st.add_vertex(t1)
		st.add_vertex(t1); st.add_vertex(b0); st.add_vertex(b1)
		st.add_vertex(t0); st.add_vertex(t1); st.add_vertex(b0)
		st.add_vertex(t1); st.add_vertex(b1); st.add_vertex(b0)
	st.generate_normals()
	return st.commit()


# ================================================================ 動き
## speed: 水平速度 m/s, on_floor: 接地, vertical_velocity: 上下速度, yaw_rate: 向きの変化 rad/s,
## forward_dot: 進行方向と体の向きの内積（数式版では未使用）
func update_motion(speed: float, on_floor: bool, vertical_velocity: float, yaw_rate: float, _forward_dot: float, delta: float) -> void:
	if _shape_key != _shape_signature():
		_build()

	_time += delta
	_speed_s = lerpf(_speed_s, speed, clampf(10.0 * delta, 0.0, 1.0))
	_yaw_rate_s = lerpf(_yaw_rate_s, yaw_rate, clampf(6.0 * delta, 0.0, 1.0))

	var walk_speed: float = Tuning.walk_speed
	var run_speed: float = Tuning.run_speed
	var target_move := clampf(_speed_s / maxf(walk_speed * 0.5, 0.1), 0.0, 1.0)
	var target_run := clampf((_speed_s - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	_move = lerpf(_move, target_move, clampf(8.0 * delta, 0.0, 1.0))
	_run = lerpf(_run, target_run, clampf(5.0 * delta, 0.0, 1.0))
	_air = lerpf(_air, 0.0 if on_floor else 1.0, clampf(10.0 * delta, 0.0, 1.0))

	if on_floor and not _was_on_floor:
		_squash = clampf(absf(vertical_velocity) / 9.0, 0.25, 1.0)
	_was_on_floor = on_floor
	_squash = move_toward(_squash, 0.0, 2.5 * delta)

	# 歩行サイクル: 1歩の長さ（歩幅）で進める。1サイクル = 2歩
	var stride := lerpf(Tuning.anim_stride_walk, Tuning.anim_stride_run, _run) * Tuning.body_scale * Tuning.leg_length
	if on_floor and _move > 0.02:
		_cycle += _speed_s / (2.0 * stride) * delta

	_apply_pose(stride, delta)


func _apply_pose(stride: float, delta: float) -> void:
	var move := _move * (1.0 - _air)
	var run := _run
	var idle := 1.0 - move
	var L := _thigh + _shin

	# ---- 歩行パラメータ ----
	var stance_frac := lerpf(0.62, 0.40, run)           # 接地している割合（走りは両足が浮く時間がある）
	var reach := stance_frac * stride                   # 足が前後に出る量
	var lift := lerpf(0.07, 0.16, run) * Tuning.body_scale  # 振り出し時の足の高さ
	var bob_amp := lerpf(0.025, 0.05, run) * Tuning.anim_bounce
	var lean := lerpf(3.0, Tuning.anim_lean_run, run) * move
	var arm_amp := lerpf(22.0, 50.0, run) * Tuning.anim_arm_swing
	var elbow_base := lerpf(20.0, 85.0, run)

	# ---- 骨盤の高さ: 伸びた脚が届く高さを基準に、歩幅に応じて上下 ----
	# 前脚はほぼ伸びて接地し、後脚は踵を上げて蹴るので、両足が届く高さより少し高めにする
	var eff := reach * 0.72
	var h_low := sqrt(maxf(L * L - eff * eff, 0.01)) + _ankle_h - 0.01
	var h_stand := L + _ankle_h - 0.02 * Tuning.body_scale
	var p_left := fposmod(_cycle, 1.0)
	var bobf := 0.5 + 0.5 * cos(TAU * 2.0 * (p_left - stance_frac * 0.5))
	var h_gait := h_low + bob_amp * bobf
	var hips_h := lerpf(h_stand, h_gait, move)
	# 待機の体重移動（ゆっくり左右へ）
	var shift := sin(_time * TAU / 7.0) * idle
	hips_h -= absf(shift) * 0.012
	# 空中は脚を畳む、着地で沈む
	hips_h = lerpf(hips_h, h_stand - 0.06, _air)
	hips_h -= _squash * 0.16 * Tuning.body_scale

	# ---- 脚: 足の位置を決めて IK ----
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var p := fposmod(_cycle + (0.0 if side == 0 else 0.5), 1.0)
		var fwd := 0.0        # 足首の前後位置（+ が前）
		var up := 0.0         # 地面からの高さ
		var foot_pitch := 0.0 # 足の角度（+ でつま先上がり）
		if p < stance_frac:
			var u := p / stance_frac
			fwd = lerpf(reach, -reach, u)
			# 踵接地 → 足裏 → つま先で蹴る
			foot_pitch = lerpf(8.0, 0.0, clampf(u * 4.0, 0.0, 1.0))
			var push := clampf((u - 0.55) / 0.45, 0.0, 1.0)
			up = push * push * 0.10 * Tuning.body_scale
			foot_pitch -= push * 30.0
		else:
			var u := (p - stance_frac) / (1.0 - stance_frac)
			var e := smoothstep(0.0, 1.0, u)
			fwd = lerpf(-reach, reach, e)
			up = sin(u * PI) * lift
			foot_pitch = lerpf(-20.0, 10.0, e)
		# 待機姿勢との合成
		var stand_fwd := shift * sx * -0.01
		fwd = lerpf(stand_fwd, fwd, move)
		up = lerpf(0.0, up, move)
		foot_pitch = lerpf(0.0, foot_pitch, move)
		# 空中: 前脚を上げ、後脚を後ろに
		var air_fwd := 0.18 if side == 0 else -0.16
		var air_up := 0.30 if side == 0 else 0.12
		fwd = lerpf(fwd, air_fwd * Tuning.body_scale, _air)
		up = lerpf(up, air_up * Tuning.body_scale, _air)
		foot_pitch = lerpf(foot_pitch, -15.0, _air)

		var lateral := sx * (_hip_w + 0.02 * Tuning.body_scale)
		var target := Vector3(lateral, -hips_h + _ankle_h + up, -fwd)
		_solve_leg(side, target, foot_pitch, delta)

	# ---- 骨盤・胸・首・頭 ----
	var leg_phase := cos(TAU * p_left)                  # +1 で左脚が前
	var pelvis_yaw := -leg_phase * 5.0 * move
	var pelvis_roll := -sin(TAU * p_left) * 3.0 * move + shift * 2.0
	var pelvis_x := -sin(TAU * p_left) * 0.015 * move + shift * 0.02
	var breath := sin(_time * TAU / 4.2)
	var turn_lean := clampf(rad_to_deg(_yaw_rate_s) * 0.06, -8.0, 8.0) * move

	_hips.position = _hips.position.lerp(Vector3(pelvis_x, hips_h, 0), clampf(20.0 * delta, 0.0, 1.0))
	_set_rot(_hips, Vector3(deg_to_rad(-lean * 0.3 - _squash * 6.0), deg_to_rad(pelvis_yaw), deg_to_rad(pelvis_roll)), delta)
	_set_rot(_spine, Vector3(deg_to_rad(-lean * 0.4 - _squash * 8.0 + breath * 0.6 * idle), deg_to_rad(-pelvis_yaw * 0.6), deg_to_rad(-pelvis_roll * 0.5)), delta)
	_set_rot(_chest, Vector3(deg_to_rad(-lean * 0.3 - _air * 6.0), deg_to_rad(-pelvis_yaw * 0.8), deg_to_rot(turn_lean * 0.5 - pelvis_roll * 0.3)), delta)
	_chest.scale = Vector3(1, 1, 1 + breath * 0.02 * idle)
	# 首と頭: 胸の回転を打ち消して前を向き続ける。待機ではゆっくり見回す
	var look := (sin(_time * TAU / 9.0) * 10.0 + sin(_time * TAU / 3.7) * 3.0) * idle
	_set_rot(_neck, Vector3(deg_to_rad(lean * 0.5 + breath * 0.5 * idle), deg_to_rad(pelvis_yaw * 0.4 + look * 0.4), deg_to_rad(-turn_lean * 0.3)), delta)
	_set_rot(_head, Vector3(deg_to_rad(breath * 0.8 * idle - _squash * 5.0), deg_to_rad(look * 0.6), 0), delta)
	_set_rot(_root, Vector3(0, 0, deg_to_rad(turn_lean)), delta)

	# ---- 腕: 脚と逆位相。肘は前に曲がる ----
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var p := fposmod(_cycle + (0.0 if side == 0 else 0.5), 1.0)
		var arm_phase := -cos(TAU * p)                  # 左脚が前のとき左腕は後ろ
		var flex := arm_phase * arm_amp * move + shift * sx * 2.0
		var elbow := 12.0 + elbow_base * move + maxf(0.0, arm_phase) * 12.0 * move
		var abduct := 6.0 + run * 8.0 * move
		# 空中: 腕を前上へ。着地: 腕を少し開く
		flex = lerpf(flex, 45.0, _air)
		elbow = lerpf(elbow, 50.0, _air)
		abduct += _squash * 20.0 + _air * 15.0
		_set_rot(_clavicle[side], Vector3(0, 0, deg_to_rad(sx * -breath * 1.0 * idle)), delta)
		_set_rot(_shoulder[side], Vector3(deg_to_rad(flex), 0, deg_to_rad(sx * -abduct)), delta)
		_set_rot(_elbow[side], Vector3(deg_to_rad(elbow), 0, 0), delta)
		_set_rot(_wrist[side], Vector3(deg_to_rad(-10.0), 0, deg_to_rad(sx * 8.0)), delta)

	# ---- コートの裾: 大腿に少し遅れて追従。走ると後ろへ流れ、空中でふわっと開く ----
	for side in 2:
		var sx := -1.0 if side == 0 else 1.0
		var thigh_x := _hip[side].rotation.x
		var flap_x := thigh_x * 0.45 - deg_to_rad(run * move * 10.0) - deg_to_rad(_air * 20.0)
		var flap_z := deg_to_rad(sx * (5.0 + run * move * 8.0 + _air * 12.0))
		_set_rot(_coat[side], Vector3(flap_x, 0, flap_z), delta * 0.6)


## 2本骨 IK: 骨盤ローカル座標の足首位置 target から、股と膝の角度を求める
func _solve_leg(side: int, target: Vector3, foot_pitch_deg: float, delta: float) -> void:
	var sx := -1.0 if side == 0 else 1.0
	var hip_pos := Vector3(sx * _hip_w, 0, 0)
	var t := target - hip_pos
	var L1 := _thigh
	var L2 := _shin
	var d := clampf(t.length(), absf(L1 - L2) + 0.01, L1 + L2 - 0.004)
	# 矢状面（前後）の角度。rotation.x が + で足が前へ出る
	var a_t := atan2(-t.z, -t.y)
	var alpha := acos(clampf((L1 * L1 + d * d - L2 * L2) / (2.0 * L1 * d), -1.0, 1.0))
	var beta := acos(clampf((L1 * L1 + L2 * L2 - d * d) / (2.0 * L1 * L2), -1.0, 1.0))
	var thigh_rot := a_t + alpha        # 膝は股-足首の線より前に出る
	var knee_rot := -(PI - beta)        # 膝は後ろに曲がる（下腿が後ろへ）
	# 横方向: 足を股の真下より少し外に
	var lateral := atan2(-(t.x) * sx, -t.y) * sx
	_set_rot(_hip[side], Vector3(thigh_rot, 0, -lateral), delta, 25.0)
	_set_rot(_knee[side], Vector3(knee_rot, 0, 0), delta, 25.0)
	# 足首: 足裏を地面と平行に保ち、そこに踵接地 / 蹴りの角度を足す
	var ankle_rot := -(thigh_rot + knee_rot) + deg_to_rad(foot_pitch_deg)
	_set_rot(_ankle[side], Vector3(ankle_rot, 0, lateral), delta, 25.0)


func deg_to_rot(deg: float) -> float:
	return deg_to_rad(deg)


func _set_rot(node: Node3D, target: Vector3, delta: float, rate: float = 18.0) -> void:
	var t := clampf(rate * delta, 0.0, 1.0)
	node.rotation = node.rotation.lerp(target, t)


## 飛行の開始 / 終了（player.gd から）。数式の仮キャラは専用の姿勢を持たないので、空中の姿勢のまま
func set_flying(_on: bool) -> void:
	pass
