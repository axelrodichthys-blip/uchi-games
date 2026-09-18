extends CharacterBody3D
## 仮キャラ（カプセル）。カメラの向きを基準に WASD / 左スティックで移動する。
## 斜面: slope_max_angle より緩い坂は歩いて登れる。急な坂は壁扱いで滑り落ちる。
## 身体は常に垂直に立つ（一般的な3Dゲームと同じ。地面の傾きに合わせて身体は傾けない）。

@onready var body: Node3D = $Body
@onready var traveler_procedural: Node3D = $Body/Traveler
@onready var traveler_rig: Node3D = $Body/TravelerRig
@onready var camera_rig: Node3D = $CameraRig
@onready var footsteps: AudioStreamPlayer = $Footsteps

var _speed: float = 0.0
var _prev_body_yaw: float = 0.0
# よじ登り（climb）: 前に進み続けて肩〜首くらいの段差に当たったら、上に登る
var _climbing: bool = false
var _climb_from: Vector3
var _climb_to: Vector3
var _climb_t: float = 0.0
var _climb_duration: float = 0.5
var _climb_anim: bool = false   # 登りアニメを使う（高い段）か、歩いたまま（低い段）か
var _push_time: float = 0.0   # 壁を押し続けている時間
var _jump_buffer: float = 0.0 # ジャンプの先行入力（短いタップや着地直前の入力を拾う）
var _flying: bool = false     # 飛行中（F キー / パッド Y で入り切り）
var _fly_lean: float = 0.0    # 今の身体の傾き 度（急に変わらないようにならしている）


func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	# 足音: アニメの接地に合わせて鳴らす。音の組はワールドが決める
	if traveler_rig.has_signal("footstep"):
		traveler_rig.footstep.connect(footsteps.on_step)
	var world := get_parent()
	if world is WorldBase:
		footsteps.set_surface(world.footstep_set)


func _physics_process(delta: float) -> void:
	floor_max_angle = deg_to_rad(Tuning.slope_max_angle)
	floor_snap_length = Tuning.floor_snap
	if _climbing:
		_update_climb(delta)
		return

	# 飛行の入り切り
	if Input.is_action_just_pressed("fly") and int(Tuning.fly_mode) == 1:
		_set_flying(not _flying)
	if _flying and int(Tuning.fly_mode) != 1:
		_set_flying(false)
	if _flying:
		_fly(delta)
		return

	# 重力・ジャンプ。押した瞬間を少しの間覚えておく（タップが短くても、着地の直前でも跳べる）
	if Input.is_action_just_pressed("jump"):
		_jump_buffer = Tuning.jump_buffer_time
	else:
		_jump_buffer = maxf(_jump_buffer - delta, 0.0)
	if is_on_floor():
		if _jump_buffer > 0.0:
			velocity.y = Tuning.jump_velocity
			_jump_buffer = 0.0
	else:
		velocity.y -= Tuning.gravity * delta

	# 入力 → カメラ基準の方向
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	if input.length_squared() > 0.0:
		dir = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_rig.get_yaw())
		dir = dir.limit_length(1.0)

	var target_speed := (Tuning.run_speed if Input.is_action_pressed("run") else Tuning.walk_speed) * dir.length()
	var rate := Tuning.acceleration if target_speed > _speed else Tuning.deceleration
	_speed = move_toward(_speed, target_speed, rate * delta)

	var horizontal := velocity
	horizontal.y = 0.0
	if is_on_floor():
		if dir.length_squared() > 0.0:
			horizontal = horizontal.move_toward(dir.normalized() * _speed, rate * delta)
		else:
			horizontal = horizontal.move_toward(Vector3.ZERO, rate * delta)
	elif dir.length_squared() > 0.0:
		# 空中: 慣性を保ったまま、少しだけ操作できる（急斜面で滑るときも勢いを殺さない）
		horizontal = horizontal.move_toward(dir.normalized() * _speed, Tuning.air_control * rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	# 身体の向き
	if camera_rig.first_person:
		body.rotation.y = camera_rig.get_yaw()
	elif dir.length_squared() > 0.0:
		var want := atan2(-dir.x, -dir.z)
		body.rotation.y = lerp_angle(body.rotation.y, want, clampf(Tuning.turn_speed * delta, 0.0, 1.0))

	body.visible = not camera_rig.first_person
	move_and_slide()
	# 段差: 進もうとして壁に当たっているとき、目の前の段に登れるか調べる
	if dir.length_squared() > 0.0 and is_on_wall() and is_on_floor():
		_push_time += delta
		if _try_start_climb(dir.normalized()):
			return
	else:
		_push_time = 0.0
	var yaw_rate := angle_difference(_prev_body_yaw, body.rotation.y) / delta
	_prev_body_yaw = body.rotation.y
	# 進行方向と体の向き（-Z が前）の内積。一人称で後ろ歩きしたときに -1 になる
	var forward := -body.global_basis.z
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var forward_dot := 1.0
	if horizontal_speed > 0.1:
		forward_dot = forward.dot(Vector3(velocity.x, 0, velocity.z) / horizontal_speed)
	_active_model().update_motion(horizontal_speed, is_on_floor(), velocity.y, yaw_rate, forward_dot, delta)


## 飛行の入り切り。地上から入るときは少し浮き上がる
func _set_flying(on: bool) -> void:
	if _flying == on:
		return
	_flying = on
	if on and velocity.y < Tuning.fly_takeoff:
		velocity.y = Tuning.fly_takeoff
	if not on:
		_fly_lean = 0.0
		body.rotation.x = 0.0
	var model := _active_model()
	if model.has_method("set_flying"):
		model.set_flying(on)


## 飛行中の動き。重力は効かず、空中を自由に進む
func _fly(delta: float) -> void:
	var input := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var dir := Vector3.ZERO
	if input.length_squared() > 0.0:
		dir = Vector3(input.x, 0.0, input.y).rotated(Vector3.UP, camera_rig.get_yaw()).limit_length(1.0)
	var rise := 0.0
	if Input.is_action_pressed("jump"):
		rise += 1.0
	if Input.is_action_pressed("descend"):
		rise -= 1.0

	var speed: float = Tuning.fly_boost_speed if Input.is_action_pressed("run") else Tuning.fly_speed
	var want := dir * speed
	want.y = rise * Tuning.fly_rise_speed
	# 入力があるところは加速、無いところはゆっくり止まる（ふわっと滑る感じ）
	var accel: float = Tuning.fly_accel
	var damp: float = Tuning.fly_damp
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	var want_flat := Vector3(want.x, 0.0, want.z)
	flat = flat.move_toward(want_flat, (accel if dir.length_squared() > 0.0 else damp) * delta)
	velocity.x = flat.x
	velocity.z = flat.z
	velocity.y = move_toward(velocity.y, want.y, (accel if absf(rise) > 0.01 else damp) * delta)

	# 高く上がりすぎないように（世界の外へ出ないための保険）
	if global_position.y > Tuning.fly_max_height and velocity.y > 0.0:
		velocity.y = 0.0

	# 身体の向きと、進む向きへの傾き
	if camera_rig.first_person:
		body.rotation.y = camera_rig.get_yaw()
	elif dir.length_squared() > 0.0:
		var yaw := atan2(-dir.x, -dir.z)
		body.rotation.y = lerp_angle(body.rotation.y, yaw, clampf(Tuning.turn_speed * delta, 0.0, 1.0))
	var flat_speed := Vector2(velocity.x, velocity.z).length()
	var want_lean: float = Tuning.fly_lean * clampf(flat_speed / maxf(Tuning.fly_speed, 0.1), 0.0, 1.0)
	if camera_rig.first_person:
		want_lean = 0.0
	_fly_lean = lerpf(_fly_lean, want_lean, clampf(4.0 * delta, 0.0, 1.0))
	body.rotation.x = -deg_to_rad(_fly_lean)

	body.visible = not camera_rig.first_person
	move_and_slide()
	# 地面に触れて、上昇していなければ着地して飛行をやめる
	if is_on_floor() and rise <= 0.0:
		_set_flying(false)
		return
	var yaw_rate := angle_difference(_prev_body_yaw, body.rotation.y) / delta
	_prev_body_yaw = body.rotation.y
	_active_model().update_motion(flat_speed, false, velocity.y, yaw_rate, 1.0, delta)


func _active_model() -> Node3D:
	var use_rig := int(Tuning.character_model) == 0
	traveler_rig.visible = use_rig
	traveler_procedural.visible = not use_rig
	return traveler_rig if use_rig else traveler_procedural


## 目の前の段の上面を探す。戻り値: {"landing": Vector3, "rise": float} または空。
## レイで「足元の高さに障害物がある」「max_h の高さでは前が空いている」「その先に立てる面がある」を確かめ、
## 最後にカプセルがその場所に収まるかを形状判定で確かめる（test_move はめり込み状態に弱いので使わない）
func _find_ledge(dir: Vector3, max_h: float) -> Dictionary:
	var space := get_world_3d().direct_space_state
	var feet := global_position
	var reach := dir * 0.5   # カプセル半径 0.3 + 余裕
	var mask := 1 | 4         # 地形 + 小物
	var ex: Array[RID] = [get_rid()]
	var low := PhysicsRayQueryParameters3D.create(feet + Vector3.UP * 0.08, feet + Vector3.UP * 0.08 + reach, mask, ex)
	if space.intersect_ray(low).is_empty():
		return {}   # 足元に障害物が無い
	var top_y := feet.y + max_h + 0.1
	var high := PhysicsRayQueryParameters3D.create(Vector3(feet.x, top_y, feet.z), Vector3(feet.x, top_y, feet.z) + reach, mask, ex)
	if not space.intersect_ray(high).is_empty():
		return {}   # max_h の高さでも壁がある（高すぎる）
	var down := PhysicsRayQueryParameters3D.create(Vector3(feet.x, top_y, feet.z) + reach, feet + reach + Vector3.UP * 0.02, mask, ex)
	var top := space.intersect_ray(down)
	if top.is_empty():
		return {}
	var normal: Vector3 = top["normal"]
	if normal.y < cos(floor_max_angle):
		return {}   # 段の上が急斜面
	var landing: Vector3 = top["position"]
	var rise := landing.y - feet.y
	if rise < 0.05 or rise > max_h:
		return {}
	# その場所にカプセルが収まるか（少し細くして判定）
	var probe := PhysicsShapeQueryParameters3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 1.5
	probe.shape = capsule
	probe.transform = Transform3D(Basis.IDENTITY, landing + Vector3.UP * (0.8 + 0.06))
	probe.collision_mask = mask
	probe.exclude = ex
	if not space.intersect_shape(probe, 1).is_empty():
		return {}
	return {"landing": landing, "rise": rise}


## 段差: 膝までは歩いたまま足で（短い登り動作、アニメはそのまま）、肩〜首までは腕で登る（登りアニメ）
func _try_start_climb(dir: Vector3) -> bool:
	var ledge := _find_ledge(dir, Tuning.climb_height)
	if ledge.is_empty():
		return false
	var rise: float = ledge["rise"]
	var big := rise > Tuning.step_height
	if big and _push_time < 0.12:
		return false   # 高い段は「押し続けたら」登る
	_climbing = true
	_climb_from = global_position
	_climb_to = ledge["landing"] + Vector3.UP * 0.02
	_climb_t = 0.0
	_climb_duration = Tuning.climb_time if big else clampf(rise / maxf(Tuning.step_height, 0.01) * 0.25, 0.08, 0.25)
	_climb_anim = big
	_push_time = 0.0
	velocity = Vector3.ZERO
	if not camera_rig.first_person:
		body.rotation.y = atan2(-dir.x, -dir.z)
	var model := _active_model()
	if big and model.has_method("set_climbing"):
		model.set_climbing(true)
	return true


## 登っている間: 上へ上がってから前へ出る軌道で、当たり判定を無視して移動する
func _update_climb(delta: float) -> void:
	_climb_t = minf(_climb_t + delta / maxf(_climb_duration, 0.05), 1.0)
	var up_part := clampf(_climb_t / 0.6, 0.0, 1.0)
	var fwd_part := clampf((_climb_t - 0.4) / 0.6, 0.0, 1.0)
	var y := lerpf(_climb_from.y, _climb_to.y, up_part * up_part * (3.0 - 2.0 * up_part))
	var xz := _climb_from.lerp(_climb_to, fwd_part * fwd_part * (3.0 - 2.0 * fwd_part))
	global_position = Vector3(xz.x, y, xz.z)
	var model := _active_model()
	# 低い段は歩きアニメのまま（速さを渡して足を動かし続ける）
	model.update_motion(0.0 if _climb_anim else _speed, true, 0.0, 0.0, 1.0, delta)
	if _climb_t >= 1.0:
		_climbing = false
		velocity = Vector3.ZERO
		if _climb_anim and model.has_method("set_climbing"):
			model.set_climbing(false)
