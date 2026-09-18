extends Control
## スマホ・タブレット用のタッチ操作。指を何本使っても効くよう、画面のタッチを自分で仕分ける。
##   画面の左下側 … 触れた場所に仮想スティックが出る。ドラッグで移動（傾け具合が速さになる）
##   それ以外     … 1 本指でなぞると視点、2 本指でつまむとカメラの距離（ズーム）
##   右下のボタン … ジャンプ（飛行中は上昇）/ 走る（タップで入り切り。飛行中は加速）/ 降りる（飛行中の下降）
##   右上のボタン … 飛ぶ（F）/ 視点（一人称 / 三人称）/ 調整（F1）/ 次のワールド（F2）
##
## 大きさは画面の短いほうの辺に対する割合で決める（端末の解像度が違っても指で押せる大きさになる）。
## F1 の touch_ui_scale で全体の大きさ、touch_stick_radius でスティックの大きさを変えられる。
##
## 表示は Tuning.touch_controls（0=自動 / 1=常に表示 / 2=隠す）。
## 自動はタッチ画面を持つ端末か、最初に画面に触れたときに出る（PC では出ない）。
## WorldBase がすべてのワールドに自動で足すので、ワールド側で用意する必要はない。

const STICK_ZONE_W := 0.48     # 画面の左からこの割合までがスティックの領域
const STICK_ZONE_TOP := 0.32   # 画面の上からこの割合より下がスティックの領域
const ACTION_OF := {"jump": "jump", "run": "run", "view": "toggle_view",
	"debug": "toggle_debug", "world": "next_world", "fly": "fly", "descend": "descend"}

var _unit: float = 100.0       # 画面の短いほうの辺。ボタンの大きさはこれに対する割合で決める
var _stick_index: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _look: Dictionary = {}     # 視点・ズーム用の指: 指の番号 -> 今の位置
var _pinch_prev: float = -1.0  # 直前の 2 本指の間隔
var _button_of: Dictionary = {}   # 指の番号 -> ボタン名
var _run_on: bool = false      # 走る（タップで入り切り。押しっぱなしは指がつらい）
var _seen_touch: bool = false
var _font: Font


func _ready() -> void:
	_font = ThemeDB.fallback_font
	set_process_unhandled_input(true)


func _process(_delta: float) -> void:
	var want := _should_show()
	if visible != want:
		visible = want
		if not want:
			_release_all()
	if visible:
		_unit = minf(size.x, size.y) * clampf(Tuning.touch_ui_scale, 0.5, 2.0)
		queue_redraw()


func _should_show() -> bool:
	match int(Tuning.touch_controls):
		1: return true
		2: return false
		_: return _seen_touch or DisplayServer.is_touchscreen_available()


# ---------------------------------------------------------------- 入力
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_seen_touch = true
		if not visible:
			return
		if event.pressed:
			_on_press(event.index, event.position)
		else:
			_on_release(event.index)
		get_viewport().set_input_as_handled()
	elif event is InputEventScreenDrag and visible:
		if event.index == _stick_index:
			_stick_pos = event.position
			_apply_stick()
		elif _look.has(event.index):
			_look[event.index] = event.position
			_apply_look(event)
		get_viewport().set_input_as_handled()


func _on_press(index: int, pos: Vector2) -> void:
	for b in _buttons():
		if _hit(b, pos):
			_button_of[index] = b["id"]
			_press_button(b["id"], true)
			return
	if pos.x < size.x * STICK_ZONE_W and pos.y > size.y * STICK_ZONE_TOP and _stick_index < 0:
		_stick_index = index
		_stick_origin = pos
		_stick_pos = pos
		_apply_stick()
		return
	if _look.size() < 2:
		_look[index] = pos
		_pinch_prev = -1.0


func _on_release(index: int) -> void:
	if _button_of.has(index):
		_press_button(_button_of[index], false)
		_button_of.erase(index)
	if index == _stick_index:
		_stick_index = -1
		_release_move()
	if _look.has(index):
		_look.erase(index)
		_pinch_prev = -1.0


## 1 本指なら視点、2 本指ならつまんでズーム
func _apply_look(event: InputEventScreenDrag) -> void:
	var camera_rig: Node = _camera_rig()
	if camera_rig == null:
		return
	if _look.size() >= 2:
		var points: Array = _look.values()
		var dist: float = (points[0] as Vector2).distance_to(points[1])
		if _pinch_prev > 0.0:
			# 指を広げると近づく（拡大）、狭めると離れる
			camera_rig.zoom((_pinch_prev - dist) / maxf(_unit, 1.0) * Tuning.touch_zoom_speed)
		_pinch_prev = dist
	else:
		camera_rig.add_look(event.relative * Tuning.touch_look_sensitivity)


## スティックの傾きを移動の入力にする（傾けるほど速い）
func _apply_stick() -> void:
	var radius := _stick_radius()
	var v := (_stick_pos - _stick_origin) / maxf(radius, 1.0)
	if v.length() > 1.0:
		# 大きく動かしたらスティックの中心を引きずる（指を追いかける）
		_stick_origin = _stick_pos - v.normalized() * radius
		v = v.normalized()
	_axis("move_left", "move_right", v.x)
	_axis("move_forward", "move_back", v.y)   # 画面の下方向が +y = 後退


func _axis(neg: String, pos: String, value: float) -> void:
	var dead := 0.12
	if value > dead:
		Input.action_release(neg)
		Input.action_press(pos, clampf((value - dead) / (1.0 - dead), 0.0, 1.0))
	elif value < -dead:
		Input.action_release(pos)
		Input.action_press(neg, clampf((-value - dead) / (1.0 - dead), 0.0, 1.0))
	else:
		Input.action_release(neg)
		Input.action_release(pos)


func _release_move() -> void:
	for a in ["move_left", "move_right", "move_forward", "move_back"]:
		Input.action_release(a)


func _release_all() -> void:
	_release_move()
	for id in _button_of.values():
		_press_button(id, false)
	_button_of.clear()
	_stick_index = -1
	_look.clear()
	if _run_on:
		_run_on = false
		Input.action_release("run")


func _press_button(id: String, pressed: bool) -> void:
	# 走るだけはタップで入り切り（押しっぱなしにしなくてよい）
	if id == "run":
		if pressed:
			_run_on = not _run_on
			if _run_on:
				Input.action_press("run")
			else:
				Input.action_release("run")
		return
	var action: String = ACTION_OF.get(id, "")
	if action == "":
		return
	if pressed:
		Input.action_press(action)
	else:
		Input.action_release(action)


func _camera_rig() -> Node:
	var player := get_tree().get_first_node_in_group("player")
	return player.get_node_or_null("CameraRig") if player else null


func _stick_radius() -> float:
	return _unit * clampf(Tuning.touch_stick_radius, 0.05, 0.3)


# ---------------------------------------------------------------- 見た目
## ボタンの一覧。大きさ・位置はすべて画面の短いほうの辺（_unit）に対する割合で決める
func _buttons() -> Array:
	var u := _unit
	var w := size.x
	var h := size.y
	var list: Array = []
	var jump_r := u * 0.115
	var run_r := u * 0.082
	list.append({"id": "jump", "shape": "circle", "center": Vector2(w - jump_r - u * 0.05, h - jump_r - u * 0.06), "radius": jump_r, "label": "ジャンプ"})
	list.append({"id": "run", "shape": "circle", "center": Vector2(w - jump_r * 2.0 - run_r - u * 0.09, h - run_r - u * 0.055), "radius": run_r, "label": "走る"})
	# 降りる（飛行中の下降）。ジャンプの上に置く
	list.append({"id": "descend", "shape": "circle", "center": Vector2(w - jump_r - u * 0.05, h - jump_r * 3.0 - u * 0.09), "radius": run_r, "label": "降りる"})
	var bw := u * 0.19
	var bh := u * 0.085
	var gap := u * 0.02
	var top_y := u * 0.035
	var labels := [["fly", "飛ぶ"], ["view", "視点"], ["debug", "調整"], ["world", "ワールド"]]
	for i in labels.size():
		var x: float = w - (bw + gap) * (labels.size() - i) - u * 0.02
		list.append({"id": labels[i][0], "shape": "rect", "rect": Rect2(x, top_y, bw, bh), "label": labels[i][1]})
	return list


func _hit(b: Dictionary, pos: Vector2) -> bool:
	if b["shape"] == "circle":
		return pos.distance_to(b["center"]) <= float(b["radius"]) * 1.12
	return (b["rect"] as Rect2).grow(_unit * 0.02).has_point(pos)


func _draw() -> void:
	var u := _unit
	var line_w := maxf(u * 0.004, 1.5)
	var pressed_ids: Array = _button_of.values()
	for b in _buttons():
		var on: bool = pressed_ids.has(b["id"]) or (b["id"] == "run" and _run_on)
		var fill := Color(1, 1, 1, 0.30 if on else 0.16)
		var line := Color(1, 1, 1, 0.9 if on else 0.55)
		if b["shape"] == "circle":
			var c: Vector2 = b["center"]
			var r: float = b["radius"]
			draw_circle(c, r, fill)
			draw_arc(c, r, 0.0, TAU, 48, line, line_w, true)
			_label(b["label"], c, u * 0.036)
		else:
			var rect: Rect2 = b["rect"]
			draw_rect(rect, fill, true)
			draw_rect(rect, line, false, line_w)
			_label(b["label"], rect.get_center(), u * 0.032)

	# 仮想スティック（触れている間だけ出す）
	var radius := _stick_radius()
	if _stick_index >= 0:
		draw_arc(_stick_origin, radius, 0.0, TAU, 56, Color(1, 1, 1, 0.4), line_w, true)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(radius)
		draw_circle(knob, radius * 0.42, Color(1, 1, 1, 0.34))
		draw_arc(knob, radius * 0.42, 0.0, TAU, 40, Color(1, 1, 1, 0.8), line_w, true)
	else:
		# 待機中はスティックの置き場所をうっすら示す
		var hint := Vector2(size.x * 0.2, size.y - radius - u * 0.1)
		draw_arc(hint, radius, 0.0, TAU, 56, Color(1, 1, 1, 0.16), line_w, true)
		_label("移動", hint, u * 0.034, 0.4)


func _label(text: String, center: Vector2, font_size: float, alpha: float = 0.9) -> void:
	var size_px := maxi(int(font_size), 8)
	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	draw_string(_font, center - text_size * 0.5 + Vector2(0, text_size.y * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(1, 1, 1, alpha))
