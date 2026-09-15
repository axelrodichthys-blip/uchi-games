extends CharacterBody3D
## 仮キャラ（カプセル）。カメラの向きを基準に WASD / 左スティックで移動する。
## 斜面: slope_max_angle より緩い坂は歩いて登れる。急な坂は壁扱いで滑り落ちる。
## 身体は常に垂直に立つ（一般的な3Dゲームと同じ。地面の傾きに合わせて身体は傾けない）。

@onready var body: Node3D = $Body
@onready var camera_rig: Node3D = $CameraRig

var _speed: float = 0.0


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


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
	if dir.length_squared() > 0.0:
		horizontal = horizontal.move_toward(dir.normalized() * _speed, rate * delta)
	else:
		horizontal = horizontal.move_toward(Vector3.ZERO, rate * delta)
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
