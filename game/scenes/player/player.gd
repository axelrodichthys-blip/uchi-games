extends CharacterBody3D
## 仮キャラ（カプセル）。カメラの向きを基準に WASD / 左スティックで移動する。

@onready var body: Node3D = $Body
@onready var camera_rig: Node3D = $CameraRig

var _speed: float = 0.0


func _ready() -> void:
	# 起動直後はマウスを掴まない（ブラウザではクリックが必要）。HUD に案内を出す。
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("release_mouse"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _physics_process(delta: float) -> void:
	# 重力
	if not is_on_floor():
		velocity.y -= Tuning.gravity * delta
	else:
		velocity.y = 0.0

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
