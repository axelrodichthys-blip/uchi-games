extends Node3D
## Mixamo のアニメ付きキャラ（game/assets/traveler_mixamo.glb）を動かす。
## AnimationTree をコードで組み、速度や接地状態からブレンドする。
##   地上: Idle ↔ Walking ↔ Running（速度でブレンド、足が滑らないよう再生速度も合わせる）
##         後ろ向きに動くときは WalkingBackwards
##   空中: Jump（踏切の直後）→ FallingIdle（落下）→ Landing（着地）
## player.gd から毎物理フレーム update_motion() を呼ぶ（数式の仮キャラ traveler.gd と同じ呼び方）。

const MODEL := preload("res://assets/traveler_mixamo.glb")
const LOOPING := ["Idle", "Walking", "Running", "FallingIdle", "LookAround", "WalkingBackwards"]

var _model: Node3D
var _player: AnimationPlayer
var _tree: AnimationTree
var _move: float = 0.0
var _run: float = 0.0
var _back: float = 0.0
var _speed_s: float = 0.0
var _state: String = "ground"
var _air_time: float = 0.0
var _land_timer: float = 0.0
var _idle_time: float = 0.0
var _was_on_floor: bool = true


func _ready() -> void:
	_model = MODEL.instantiate()
	add_child(_model)
	_player = _model.find_child("AnimationPlayer", true, false)
	for anim_name in _player.get_animation_list():
		var anim := _player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE
	_build_tree()


func _build_tree() -> void:
	var bt := AnimationNodeBlendTree.new()

	# 歩き・走り・後退はそれぞれ再生速度を変えられるようにする
	var names := {"Idle": "idle", "Walking": "walk", "Running": "run", "WalkingBackwards": "back",
		"Jump": "jump", "FallingIdle": "fall", "Landing": "land", "LookAround": "look"}
	for anim_name in names.keys():
		var node := AnimationNodeAnimation.new()
		node.animation = anim_name
		bt.add_node(names[anim_name], node)
	for key in ["walk", "run", "back"]:
		bt.add_node("ts_" + key, AnimationNodeTimeScale.new())
		bt.connect_node("ts_" + key, 0, key)
	# ジャンプは踏切の溜めを飛ばして途中から再生する
	bt.add_node("seek_jump", AnimationNodeTimeSeek.new())
	bt.connect_node("seek_jump", 0, "jump")

	var walk_run := AnimationNodeBlend2.new()
	bt.add_node("walk_run", walk_run)
	bt.connect_node("walk_run", 0, "ts_walk")
	bt.connect_node("walk_run", 1, "ts_run")
	var fwd_back := AnimationNodeBlend2.new()
	bt.add_node("fwd_back", fwd_back)
	bt.connect_node("fwd_back", 0, "walk_run")
	bt.connect_node("fwd_back", 1, "ts_back")
	var idle_look := AnimationNodeBlend2.new()
	bt.add_node("idle_look", idle_look)
	bt.connect_node("idle_look", 0, "idle")
	bt.connect_node("idle_look", 1, "look")
	var idle_move := AnimationNodeBlend2.new()
	bt.add_node("idle_move", idle_move)
	bt.connect_node("idle_move", 0, "idle_look")
	bt.connect_node("idle_move", 1, "fwd_back")

	var state := AnimationNodeTransition.new()
	state.input_count = 4
	state.set_input_name(0, "ground")
	state.set_input_name(1, "jump")
	state.set_input_name(2, "fall")
	state.set_input_name(3, "land")
	state.xfade_time = 0.15
	bt.add_node("state", state)
	bt.connect_node("state", 0, "idle_move")
	bt.connect_node("state", 1, "seek_jump")
	bt.connect_node("state", 2, "fall")
	bt.connect_node("state", 3, "land")
	bt.connect_node("output", 0, "state")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = bt
	_tree.anim_player = _tree.get_path_to(_player) if false else NodePath("")
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true
	_tree.set("parameters/state/transition_request", "ground")


## speed: 水平速度 m/s, on_floor: 接地, vertical_velocity: 上下速度, yaw_rate: 向きの変化 rad/s,
## forward_dot: 進行方向と体の向きの内積（+1 前進 / -1 後退）
func update_motion(speed: float, on_floor: bool, vertical_velocity: float, yaw_rate: float, forward_dot: float, delta: float) -> void:
	_speed_s = lerpf(_speed_s, speed, clampf(10.0 * delta, 0.0, 1.0))
	var walk_speed: float = Tuning.walk_speed
	var run_speed: float = Tuning.run_speed
	var target_move := clampf(_speed_s / maxf(walk_speed * 0.5, 0.1), 0.0, 1.0)
	var target_run := clampf((_speed_s - walk_speed) / maxf(run_speed - walk_speed, 0.1), 0.0, 1.0)
	var target_back := 1.0 if (forward_dot < -0.3 and speed > 0.2) else 0.0
	_move = lerpf(_move, target_move, clampf(8.0 * delta, 0.0, 1.0))
	_run = lerpf(_run, target_run, clampf(5.0 * delta, 0.0, 1.0))
	_back = lerpf(_back, target_back, clampf(8.0 * delta, 0.0, 1.0))

	# 足が滑らないよう、クリップの再生速度を実速度に合わせる
	var walk_scale := _speed_s / maxf(Tuning.anim_walk_native_speed, 0.1)
	var run_scale := _speed_s / maxf(Tuning.anim_run_native_speed, 0.1)
	_tree.set("parameters/ts_walk/scale", clampf(walk_scale, 0.5, 2.5) if _move > 0.05 else 1.0)
	_tree.set("parameters/ts_run/scale", clampf(run_scale, 0.5, 2.0))
	_tree.set("parameters/ts_back/scale", clampf(_speed_s / maxf(Tuning.anim_walk_native_speed * 0.35, 0.1), 0.5, 2.0))
	_tree.set("parameters/walk_run/blend_amount", _run)
	_tree.set("parameters/fwd_back/blend_amount", _back)
	_tree.set("parameters/idle_move/blend_amount", _move)

	# 長く立ち止まると見回す
	if _move < 0.05 and on_floor:
		_idle_time += delta
	else:
		_idle_time = 0.0
	var look := 1.0 if (_idle_time > 12.0 and fmod(_idle_time, 20.0) < 8.3) else 0.0
	var cur_look: float = _tree.get("parameters/idle_look/blend_amount")
	_tree.set("parameters/idle_look/blend_amount", lerpf(cur_look, look, clampf(2.0 * delta, 0.0, 1.0)))

	# 空中と着地
	if on_floor:
		if not _was_on_floor and _state != "ground":
			_state = "land"
			_land_timer = 0.55 if absf(vertical_velocity) > 5.0 else 0.35
			_tree.set("parameters/state/transition_request", "land")
		if _state == "land":
			_land_timer -= delta
			if _land_timer <= 0.0 or speed > walk_speed * 0.5:
				_state = "ground"
				_tree.set("parameters/state/transition_request", "ground")
		_air_time = 0.0
	else:
		_air_time += delta
		if _state == "ground" or _state == "land":
			if vertical_velocity > 1.0:
				_state = "jump"
				_tree.set("parameters/state/transition_request", "jump")
				_tree.set("parameters/seek_jump/seek_request", 0.45)
			elif _air_time > 0.2:
				_state = "fall"
				_tree.set("parameters/state/transition_request", "fall")
		elif _state == "jump" and (_air_time > 0.9 or vertical_velocity < -3.0):
			_state = "fall"
			_tree.set("parameters/state/transition_request", "fall")
	_was_on_floor = on_floor
