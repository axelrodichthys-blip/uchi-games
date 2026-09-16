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

	# 重力・ジャンプ
	if is_on_floor():
		if Input.is_action_just_pressed("jump"):
			velocity.y = Tuning.jump_velocity
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
	var yaw_rate := angle_difference(_prev_body_yaw, body.rotation.y) / delta
	_prev_body_yaw = body.rotation.y
	# 進行方向と体の向き（-Z が前）の内積。一人称で後ろ歩きしたときに -1 になる
	var forward := -body.global_basis.z
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var forward_dot := 1.0
	if horizontal_speed > 0.1:
		forward_dot = forward.dot(Vector3(velocity.x, 0, velocity.z) / horizontal_speed)
	var use_rig := int(Tuning.character_model) == 0
	traveler_rig.visible = use_rig
	traveler_procedural.visible = not use_rig
	var active: Node3D = traveler_rig if use_rig else traveler_procedural
	active.update_motion(horizontal_speed, is_on_floor(), velocity.y, yaw_rate, forward_dot, delta)
