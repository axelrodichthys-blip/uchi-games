extends Node3D
## Mixamo のアニメ付きキャラ（game/assets/traveler_mixamo.glb）を動かす。
## AnimationTree をコードで組み、速度や接地状態からブレンドする。
##   地上: Idle ↔ Walking ↔ Running（速度でブレンド、足が滑らないよう再生速度も合わせる）
##         後ろ向きに動くときは WalkingBackwards
##   空中: Jump（空中区間をゆっくり再生して滞空全体に使う）→ 長く落ちるときだけ FallingIdle → Landing（低い落下は軽い膝の沈みだけ）
## player.gd から毎物理フレーム update_motion() を呼ぶ（数式の仮キャラ traveler.gd と同じ呼び方）。
##
## マント: Skeleton3D に SpringBoneSimulator3D を足して裾を揺らす。
## アニメが骨を動かしたあとに掛かるので、歩き出し・止まり・振り向き・ジャンプで遅れて付いてくる。
## F1 の cloth_sway で入り切り、cloth_stiffness / drag / gravity / radius で硬さを変えられる。
##
## Mixamo のクリップに対する補正（_ready で行う）:
##   - モデルは +Z が正面なので 180 度回して Godot の前（-Z）に向ける
##   - Jump / FallingIdle / Landing は腰の位置トラックに「跳び上がる高さ」が入っている。
##     高さは物理（CharacterBody3D）が動かすので、腰が立ち姿勢より上に浮く分は取り除き、
##     しゃがみ（下がる分）だけ残す。水平のずれも取り除く

## マントを揺らすための骨の鎖（Cape0_0 …）を足した .glb。
## 元は assets/traveler_mixamo.glb で、tools/blender/add_cloth_bones.py で作り直せる
const MODEL := preload("res://assets/traveler_cloth.glb")
const CLOTH_PREFIX := "Cape"   # 布の骨の名前の頭（add_cloth_bones.py の BONE_PREFIX と合わせる）
const LOOPING := ["Idle", "Walking", "Running", "FallingIdle", "LookAround", "WalkingBackwards"]
const AIR_CLIPS := ["Jump", "FallingIdle", "Landing"]
const FOOT_BONES := ["mixamorig_LeftFoot", "mixamorig_RightFoot"]
const ARM_BONE_KEYS := ["Shoulder", "Arm", "ForeArm", "Hand"]   # 腕の骨（トラックのパスにこの語を含む）
const FOOT_DOWN := 0.225       # 足首の骨がこの高さ（m、キャラの足元基準）を下回ったら接地
const FOOT_UP := 0.255         # この高さを超えたら「持ち上がった」（ヒステリシス）

## 足が地面に着いた。side: 0 = 左 / 1 = 右、strength: 0〜1（速いほど・落下が強いほど大）
signal footstep(side: int, strength: float)
const JUMP_SEEK := 0.65        # Jump クリップのこの時刻から再生（腕を広げる踏切の溜めを飛ばし、脚を畳む所から）
const JUMP_SCALE := 0.35       # Jump の空中区間（約 0.35 秒）をこの倍率で引き伸ばし、通常のジャンプ（滞空 1.2 秒）を覆う
const FALL_AFTER := 1.0        # これより長く空中にいたら落下ポーズ（FallingIdle）へ。崖から落ちたときなど
const LAND_SOFT_SEEK := 0.5    # 軽い着地: Landing クリップのこの時刻（浅いしゃがみ）から
const LAND_SOFT_TIME := 0.32
const LAND_HARD_SEEK := 0.3    # 強い着地: 足が着いた直後（深いしゃがみ）から
const LAND_HARD_TIME := 0.6
const LAND_HARD_SPEED := 8.0   # この落下速度 m/s 以上で強い着地
const CLIMB_SEEK := 0.72       # よじ登り: Jump クリップの脚を畳んだ姿勢をゆっくり流す（専用クリップが無いので仮）
const CLIMB_SCALE := 0.25

var _model: Node3D
var _skel: Skeleton3D
var _foot_idx: Array[int] = []
var _foot_lifted: Array[bool] = [false, false]
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
var _climbing: bool = false
var _spring: SkeletonModifier3D
var _cloth_cfg := Vector4.ZERO   # 反映済みの [硬さ, 抵抗, 重力, 太さ]
var _cloth_on: int = -1


func _ready() -> void:
	_model = MODEL.instantiate()
	add_child(_model)
	_model.rotation.y = PI   # Mixamo のモデルは +Z が正面。Godot の前（-Z）に向ける
	_player = _model.find_child("AnimationPlayer", true, false)
	_skel = _model.find_child("Skeleton3D", true, false)
	if _skel:
		for bone_name in FOOT_BONES:
			_foot_idx.append(_skel.find_bone(bone_name))
	for anim_name in _player.get_animation_list():
		var anim := _player.get_animation(anim_name)
		anim.loop_mode = Animation.LOOP_LINEAR if anim_name in LOOPING else Animation.LOOP_NONE
	_fix_air_clips()
	_build_tree()
	_build_cloth()


## 空中クリップの腰の位置トラックから「立ち姿勢より上に浮く分」と水平のずれを取り除く
func _fix_air_clips() -> void:
	var skel: Skeleton3D = _model.find_child("Skeleton3D", true, false)
	if skel == null or not _player.has_animation("Idle"):
		return
	# 骨のローカル座標 → モデル座標（上下・前後の向きを合わせるため）
	var basis: Basis = (_model.global_transform.affine_inverse() * skel.global_transform).basis
	var stand := Vector3.ZERO
	var found := false
	var idle := _player.get_animation("Idle")
	for i in idle.get_track_count():
		if _is_hips_position_track(idle, i):
			stand = idle.track_get_key_value(i, 0)
			found = true
			break
	if not found:
		return
	for anim_name in AIR_CLIPS:
		if not _player.has_animation(anim_name):
			continue
		var anim := _player.get_animation(anim_name)
		for i in anim.get_track_count():
			if not _is_hips_position_track(anim, i):
				continue
			for k in anim.track_get_key_count(i):
				var v: Vector3 = anim.track_get_key_value(i, k)
				var offset: Vector3 = basis * (v - stand)
				offset = Vector3(0.0, minf(offset.y, 0.0), 0.0)
				anim.track_set_key_value(i, k, stand + basis.inverse() * offset)


func _is_hips_position_track(anim: Animation, i: int) -> bool:
	return anim.track_get_type(i) == Animation.TYPE_POSITION_3D and str(anim.track_get_path(i)).to_lower().ends_with("hips")


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
	# ジャンプは踏切の溜めを飛ばして途中から、ゆっくり再生する
	var ts_jump := AnimationNodeTimeScale.new()
	bt.add_node("ts_jump", ts_jump)
	bt.connect_node("ts_jump", 0, "jump")
	bt.add_node("seek_jump", AnimationNodeTimeSeek.new())
	bt.connect_node("seek_jump", 0, "ts_jump")
	# 着地も落下の強さで途中から再生する
	bt.add_node("seek_land", AnimationNodeTimeSeek.new())
	bt.connect_node("seek_land", 0, "land")

	var walk_run := AnimationNodeBlend2.new()
	bt.add_node("walk_run", walk_run)
	bt.connect_node("walk_run", 0, "ts_walk")
	bt.connect_node("walk_run", 1, "ts_run")
	var fwd_back := AnimationNodeBlend2.new()
	bt.add_node("fwd_back", fwd_back)
	bt.connect_node("fwd_back", 0, "walk_run")
	bt.connect_node("fwd_back", 1, "ts_back")
	# 歩き・走りの間、腕の骨だけ待機ポーズにする（Mixamo の自動リグで腕が胸にめり込むクリップの対策 + 設計上「腕を振らない」）
	var idle_arms := AnimationNodeAnimation.new()
	idle_arms.animation = "Idle"
	bt.add_node("idle_arms", idle_arms)
	var arms := AnimationNodeBlend2.new()
	arms.filter_enabled = true
	var idle_anim := _player.get_animation("Idle")
	for i in idle_anim.get_track_count():
		var path := str(idle_anim.track_get_path(i))
		var bone := path.get_slice(":", 1)
		for key in ARM_BONE_KEYS:
			if bone.ends_with(key):
				arms.set_filter_path(idle_anim.track_get_path(i), true)
				break
	bt.add_node("arms", arms)
	bt.connect_node("arms", 0, "fwd_back")
	bt.connect_node("arms", 1, "idle_arms")

	var idle_look := AnimationNodeBlend2.new()
	bt.add_node("idle_look", idle_look)
	bt.connect_node("idle_look", 0, "idle")
	bt.connect_node("idle_look", 1, "look")
	var idle_move := AnimationNodeBlend2.new()
	bt.add_node("idle_move", idle_move)
	bt.connect_node("idle_move", 0, "idle_look")
	bt.connect_node("idle_move", 1, "arms")

	# よじ登り（仮）: Jump クリップの別インスタンスをゆっくり流す
	var climb_anim := AnimationNodeAnimation.new()
	climb_anim.animation = "Jump"
	bt.add_node("climb", climb_anim)
	bt.add_node("ts_climb", AnimationNodeTimeScale.new())
	bt.connect_node("ts_climb", 0, "climb")
	bt.add_node("seek_climb", AnimationNodeTimeSeek.new())
	bt.connect_node("seek_climb", 0, "ts_climb")

	var state := AnimationNodeTransition.new()
	state.input_count = 5
	state.set_input_name(0, "ground")
	state.set_input_name(1, "jump")
	state.set_input_name(2, "fall")
	state.set_input_name(3, "land")
	state.set_input_name(4, "climb")
	state.xfade_time = 0.15
	bt.add_node("state", state)
	bt.connect_node("state", 0, "idle_move")
	bt.connect_node("state", 1, "seek_jump")
	bt.connect_node("state", 2, "fall")
	bt.connect_node("state", 3, "seek_land")
	bt.connect_node("state", 4, "seek_climb")
	bt.connect_node("output", 0, "state")

	_tree = AnimationTree.new()
	_tree.name = "AnimationTree"
	_tree.tree_root = bt
	_tree.anim_player = _tree.get_path_to(_player) if false else NodePath("")
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_player)
	_tree.active = true
	_tree.set("parameters/state/transition_request", "ground")
	_tree.set("parameters/ts_jump/scale", JUMP_SCALE)
	_tree.set("parameters/ts_climb/scale", CLIMB_SCALE)


## よじ登りの開始 / 終了（player.gd から）
func set_climbing(on: bool) -> void:
	_climbing = on
	if on:
		_state = "climb"
		_tree.set("parameters/state/transition_request", "climb")
		_tree.set("parameters/seek_climb/seek_request", CLIMB_SEEK)
	else:
		_state = "land"
		_land_timer = LAND_SOFT_TIME
		_tree.set("parameters/state/transition_request", "land")
		_tree.set("parameters/seek_land/seek_request", LAND_SOFT_SEEK)
		_was_on_floor = true


## speed: 水平速度 m/s, on_floor: 接地, vertical_velocity: 上下速度, yaw_rate: 向きの変化 rad/s,
## forward_dot: 進行方向と体の向きの内積（+1 前進 / -1 後退）
func update_motion(speed: float, on_floor: bool, vertical_velocity: float, yaw_rate: float, forward_dot: float, delta: float) -> void:
	if _climbing:
		return
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
	var cur_arms: float = _tree.get("parameters/arms/blend_amount")
	var want_arms := 0.0 if int(Tuning.arm_swing) == 1 else 1.0
	_tree.set("parameters/arms/blend_amount", lerpf(cur_arms, want_arms, clampf(6.0 * delta, 0.0, 1.0)))

	# 長く立ち止まると見回す
	if _move < 0.05 and on_floor:
		_idle_time += delta
	else:
		_idle_time = 0.0
	var look := 1.0 if (_idle_time > 12.0 and fmod(_idle_time, 20.0) < 8.3) else 0.0
	var cur_look: float = _tree.get("parameters/idle_look/blend_amount")
	_tree.set("parameters/idle_look/blend_amount", lerpf(cur_look, look, clampf(2.0 * delta, 0.0, 1.0)))

	# 足音: 足首の骨が下りてきて接地の高さを切ったら鳴らす（アニメの接地と同期する）
	if on_floor and _state == "ground" and _move > 0.1 and _skel:
		for i in _foot_idx.size():
			if _foot_idx[i] < 0:
				continue
			var foot_y := (_skel.global_transform * _skel.get_bone_global_pose(_foot_idx[i])).origin.y - global_position.y
			if foot_y > FOOT_UP:
				_foot_lifted[i] = true
			elif foot_y < FOOT_DOWN and _foot_lifted[i]:
				_foot_lifted[i] = false
				footstep.emit(i, clampf(0.35 + 0.65 * _speed_s / maxf(run_speed, 0.1), 0.0, 1.0))

	# 空中と着地
	if on_floor:
		if not _was_on_floor and _state != "ground":
			_state = "land"
			var hard := absf(vertical_velocity) >= LAND_HARD_SPEED
			footstep.emit(0, 1.0 if hard else 0.7)
			footstep.emit(1, 1.0 if hard else 0.7)
			_land_timer = LAND_HARD_TIME if hard else LAND_SOFT_TIME
			_tree.set("parameters/state/transition_request", "land")
			_tree.set("parameters/seek_land/seek_request", LAND_HARD_SEEK if hard else LAND_SOFT_SEEK)
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
				_tree.set("parameters/seek_jump/seek_request", JUMP_SEEK)
			elif _air_time > 0.2:
				_state = "fall"
				_tree.set("parameters/state/transition_request", "fall")
		elif _state == "jump" and _air_time > FALL_AFTER:
			_state = "fall"
			_tree.set("parameters/state/transition_request", "fall")
	_was_on_floor = on_floor


# ---------------------------------------------------------------- マントの揺れ
## 布の骨の鎖（Cape<n>_0 → Cape<n>_1）を SpringBoneSimulator3D に登録する。
## 骨が無い .glb（骨を足す前のもの）でも動くよう、見つからなければ何もしない
func _build_cloth() -> void:
	if _skel == null or not ClassDB.class_exists("SpringBoneSimulator3D"):
		return
	var chains: Array[Array] = []
	var ci := 0
	while true:
		var joints: Array[String] = []
		var j := 0
		while _skel.find_bone("%s%d_%d" % [CLOTH_PREFIX, ci, j]) >= 0:
			joints.append("%s%d_%d" % [CLOTH_PREFIX, ci, j])
			j += 1
		if joints.is_empty():
			break
		chains.append(joints)
		ci += 1
	if chains.is_empty():
		return
	_spring = ClassDB.instantiate("SpringBoneSimulator3D")
	_spring.name = "ClothSpring"
	_skel.add_child(_spring)
	_spring.set("setting_count", chains.size())
	for i in chains.size():
		var joints: Array = chains[i]
		_spring.call("set_root_bone_name", i, joints[0])
		_spring.call("set_end_bone_name", i, joints[joints.size() - 1])
		_spring.call("set_extend_end_bone", i, true)
		_spring.call("set_end_bone_length", i, 0.06)
	_apply_cloth(true)


## F1 の値を反映する（変わったときだけ）
func _apply_cloth(force: bool) -> void:
	if _spring == null:
		return
	var on := int(Tuning.cloth_sway)
	if force or on != _cloth_on:
		_cloth_on = on
		_spring.set("active", on == 1)
	var cfg := Vector4(Tuning.cloth_stiffness, Tuning.cloth_drag, Tuning.cloth_gravity, Tuning.cloth_radius)
	if not force and cfg.is_equal_approx(_cloth_cfg):
		return
	_cloth_cfg = cfg
	for i in int(_spring.get("setting_count")):
		_spring.call("set_stiffness", i, cfg.x)
		_spring.call("set_drag", i, cfg.y)
		_spring.call("set_gravity", i, cfg.z)
		_spring.call("set_radius", i, cfg.w)


func _process(_delta: float) -> void:
	_apply_cloth(false)
