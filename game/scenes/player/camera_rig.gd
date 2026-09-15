extends Node3D
## 三人称カメラ。マウス / 右スティックで回転、ホイールで距離、V で一人称に切替。
## マウス視点の操作方法:
##   - 右ボタンを押している間だけ視点が動く（離すとマウスが自由になる）
##   - Tab で「押しっぱなしにしなくても動く」固定モードの切替。Esc / Tab で解除
## 構造: CameraRig(ヨー) > Pitch(ピッチ) > SpringArm3D > Camera3D

@onready var pitch_node: Node3D = $Pitch
@onready var spring_arm: SpringArm3D = $Pitch/SpringArm3D
@onready var camera: Camera3D = $Pitch/SpringArm3D/Camera3D

var first_person: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _target_distance: float = 0.0
var _hold_look: bool = false      # 右ボタンを押している間
var _capture_locked: bool = false # Tab で固定したか


func _ready() -> void:
	top_level = false
	_pitch = Tuning.camera_pitch_default
	_target_distance = Tuning.camera_distance
	spring_arm.spring_length = _target_distance
	spring_arm.add_excluded_object(get_parent().get_rid())
	_apply_rotation()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT:
		_hold_look = event.pressed
		if _hold_look:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		elif not _capture_locked:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("toggle_mouse_capture"):
		set_capture_locked(not _capture_locked)
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("release_mouse"):
		set_capture_locked(false)
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: Vector2 = event.relative
		_yaw -= motion.x * Tuning.mouse_sensitivity
		var dy := motion.y * Tuning.mouse_sensitivity
		_pitch += dy if Tuning.invert_y else -dy
		_apply_rotation()
	elif event.is_action_pressed("zoom_in"):
		_change_distance(-Tuning.camera_zoom_step)
	elif event.is_action_pressed("zoom_out"):
		_change_distance(Tuning.camera_zoom_step)
	elif event.is_action_pressed("toggle_view"):
		set_first_person(not first_person)


func _process(delta: float) -> void:
	# ブラウザが Esc で強制解除したときなどに、固定状態を追従させる
	if _capture_locked and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		_capture_locked = false

	# 右スティック
	var look := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if look.length_squared() > 0.0:
		_yaw -= look.x * Tuning.stick_sensitivity * delta
		var dy := look.y * Tuning.stick_sensitivity * delta
		_pitch += dy if Tuning.invert_y else -dy
		_apply_rotation()

	# 距離・視野角を滑らかに追従
	var want_len := 0.0 if first_person else _target_distance
	var want_fov := Tuning.fov_first_person if first_person else Tuning.fov
	var t := clampf(Tuning.camera_follow_speed * delta, 0.0, 1.0)
	spring_arm.spring_length = lerpf(spring_arm.spring_length, want_len, t)
	camera.fov = lerpf(camera.fov, want_fov, t)
	var want_height := Tuning.first_person_eye_height if first_person else Tuning.camera_height
	position.y = lerpf(position.y, want_height, t)


func set_capture_locked(locked: bool) -> void:
	_capture_locked = locked
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if locked else Input.MOUSE_MODE_VISIBLE


func is_capture_locked() -> bool:
	return _capture_locked


func _change_distance(amount: float) -> void:
	if first_person:
		if amount > 0.0:
			set_first_person(false)
		return
	_target_distance = clampf(_target_distance + amount, Tuning.camera_distance_min, Tuning.camera_distance_max)
	Tuning.camera_distance = _target_distance


func set_first_person(enabled: bool) -> void:
	first_person = enabled
	if not enabled:
		_target_distance = Tuning.camera_distance


func _apply_rotation() -> void:
	_pitch = clampf(_pitch, Tuning.pitch_min, Tuning.pitch_max)
	rotation.y = deg_to_rad(_yaw)
	pitch_node.rotation.x = deg_to_rad(_pitch)


## 進行方向の計算に使う（カメラのヨーだけ）
func get_yaw() -> float:
	return rotation.y
