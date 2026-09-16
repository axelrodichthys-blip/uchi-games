extends Node3D
## 三人称カメラ。マウス / 右スティックで回転、ホイールで距離、V で一人称に切替。
## マウス視点の操作方法:
##   - 右ボタンを押している間だけ視点が動く（離すとマウスが自由になる）
##   - Tab で「押しっぱなしにしなくても動く」固定モードの切替。Esc / Tab で解除
##
## カメラと物の干渉（Tuning.camera_collision_mode）:
##   0 = すり抜け+透過: 地形だけを避ける。カメラとキャラの間にある小物は半透明にする
##   1 = 引き寄せ: 地形と小物の両方を避け、ぶつかったらカメラを手前に寄せる（寄るのは速く、戻るのはゆっくり）
##
## 構造: CameraRig(ヨー) > Pitch(ピッチ) > [ShapeCast3D, Camera3D]

const LAYER_WORLD := 1     # 地形
const LAYER_PROPS := 4     # 小物（レイヤー3）

@onready var pitch_node: Node3D = $Pitch
@onready var shape_cast: ShapeCast3D = $Pitch/ShapeCast3D
@onready var camera: Camera3D = $Pitch/Camera3D

var first_person: bool = false
var _yaw: float = 0.0
var _pitch: float = 0.0
var _target_distance: float = 0.0
var _current_distance: float = 0.0
var _hold_look: bool = false      # 右ボタンを押している間
var _capture_locked: bool = false # Tab で固定したか
var _faded: Dictionary = {}       # 透過中の GeometryInstance3D -> true
var _bob_phase: float = 0.0       # 歩行の揺れの位相（1 歩で 1 周）
var _bob_amount: float = 0.0      # 今の揺れの大きさ（滑らかに変える）


func _ready() -> void:
	_pitch = Tuning.camera_pitch_default
	_target_distance = Tuning.camera_distance
	_current_distance = _target_distance
	shape_cast.add_exception(get_parent())
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

	# 地上の移動速度（揺れと視野角に使う）
	var body := get_parent() as CharacterBody3D
	var ground_speed := 0.0
	var on_floor := true
	if body:
		ground_speed = Vector2(body.velocity.x, body.velocity.z).length()
		on_floor = body.is_on_floor()

	# 視野角: 走ると少し広げて速さを感じさせる
	var run_t := clampf((ground_speed - Tuning.walk_speed) / maxf(Tuning.run_speed - Tuning.walk_speed, 0.1), 0.0, 1.0)
	var want_fov := (Tuning.fov_first_person if first_person else Tuning.fov) + Tuning.run_fov_boost * run_t
	var t := clampf(Tuning.camera_follow_speed * delta, 0.0, 1.0)
	camera.fov = lerpf(camera.fov, want_fov, t)

	# 注視点の高さ + 歩行の揺れ（1 歩ごとに上下、2 歩で左右に 1 往復）
	var want_height := Tuning.first_person_eye_height if first_person else Tuning.camera_height
	var steps_per_meter := 1.0 / lerpf(Tuning.anim_stride_walk, Tuning.anim_stride_run, run_t)
	if on_floor and ground_speed > 0.2:
		_bob_phase = fmod(_bob_phase + ground_speed * steps_per_meter * delta, 1.0)
	var want_bob := Tuning.camera_bob * clampf(ground_speed / maxf(Tuning.walk_speed, 0.1), 0.0, 1.6) if (on_floor and ground_speed > 0.2) else 0.0
	_bob_amount = lerpf(_bob_amount, want_bob, clampf(6.0 * delta, 0.0, 1.0))
	var bob_y := -absf(sin(_bob_phase * PI)) * _bob_amount       # 着地で沈む形
	var bob_x := sin(_bob_phase * PI) * _bob_amount * 0.5
	position.y = lerpf(position.y, want_height, t) + bob_y
	position.x = bob_x

	_update_distance(delta)
	_update_occluders(delta)


## 距離: 目標距離までシェイプキャストして、ぶつかる手前に置く
func _update_distance(delta: float) -> void:
	var want := 0.0 if first_person else _target_distance
	var mode := int(Tuning.camera_collision_mode)
	shape_cast.collision_mask = LAYER_WORLD if mode == 0 else (LAYER_WORLD | LAYER_PROPS)
	shape_cast.target_position = Vector3(0, 0, want)
	shape_cast.force_shapecast_update()
	var allowed := want
	if shape_cast.is_colliding():
		allowed = maxf(want * shape_cast.get_closest_collision_safe_fraction(), 0.0)
	# 寄るのは速く、戻るのはゆっくり（一般的な三人称カメラの作法）
	var speed := Tuning.camera_pull_in_speed if allowed < _current_distance else Tuning.camera_pull_out_speed
	if first_person:
		speed = Tuning.camera_follow_speed
	_current_distance = lerpf(_current_distance, allowed, clampf(speed * delta, 0.0, 1.0))
	camera.position = Vector3(0, 0, _current_distance)


## 透過: カメラとキャラの間にある小物を半透明にする
func _update_occluders(delta: float) -> void:
	var hits: Dictionary = {}
	if not first_person and Tuning.occluder_fade > 0.0:
		var space := get_world_3d().direct_space_state
		var from := camera.global_position
		var to := global_position
		var exclude: Array[RID] = [get_parent().get_rid()]
		for i in 6:
			var query := PhysicsRayQueryParameters3D.create(from, to, LAYER_PROPS, exclude)
			var hit := space.intersect_ray(query)
			if hit.is_empty():
				break
			var collider: Node = hit.get("collider")
			if collider:
				for child in collider.get_children():
					if child is GeometryInstance3D:
						hits[child] = true
				exclude.append(hit["rid"])
			from = hit["position"]

	var t := clampf(8.0 * delta, 0.0, 1.0)
	for geom in hits.keys():
		_faded[geom] = true
	for geom in _faded.keys():
		if not is_instance_valid(geom):
			_faded.erase(geom)
			continue
		var target := Tuning.occluder_fade if hits.has(geom) else 0.0
		geom.transparency = lerpf(geom.transparency, target, t)
		if not hits.has(geom) and geom.transparency < 0.01:
			geom.transparency = 0.0
			_faded.erase(geom)


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
