extends Control
## スマホ・タブレット用のタッチ操作。指を何本使っても効くよう、画面のタッチを自分で仕分ける。
##   画面の左側   … 触れた場所に仮想スティックが出る。ドラッグで移動（傾け具合が速さになる）
##   画面の右側   … ドラッグで視点
##   右下のボタン … ジャンプ / 走る（押している間）
##   右上のボタン … 視点（一人称 / 三人称）/ 調整（F1）/ 次のワールド（F2）
##
## 表示は Tuning.touch_controls（0=自動 / 1=常に表示 / 2=隠す）。
## 自動はタッチ画面を持つ端末か、最初に画面に触れたときに出る（PC では出ない）。
## WorldBase がすべてのワールドに自動で足すので、ワールド側で用意する必要はない。

const STICK_ZONE_W := 0.45     # 画面の左からこの割合までがスティックの領域
const STICK_ZONE_TOP := 0.30   # 画面の上からこの割合より下がスティックの領域
const ACTION_OF := {"jump": "jump", "run": "run", "view": "toggle_view",
	"debug": "toggle_debug", "world": "next_world"}

var _ui_scale: float = 1.0
var _stick_index: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_pos: Vector2 = Vector2.ZERO
var _look_index: int = -1
var _button_of: Dictionary = {}   # 指の番号 -> ボタン名
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
		_ui_scale = clampf(minf(size.x, size.y) / 720.0, 0.65, 1.8)
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
		elif event.index == _look_index:
			var camera_rig: Node = _camera_rig()
			if camera_rig:
				camera_rig.add_look(event.relative * Tuning.touch_look_sensitivity)
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
	if _look_index < 0:
		_look_index = index


func _on_release(index: int) -> void:
	if _button_of.has(index):
		_press_button(_button_of[index], false)
		_button_of.erase(index)
	if index == _stick_index:
		_stick_index = -1
		_release_move()
	if index == _look_index:
		_look_index = -1


## スティックの傾きを移動の入力にする（傾けるほど速い）
func _apply_stick() -> void:
	var radius := Tuning.touch_stick_radius * _ui_scale
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
	_look_index = -1


func _press_button(id: String, pressed: bool) -> void:
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


# ---------------------------------------------------------------- 見た目
## ボタンの一覧（画面の大きさから毎回計算する）
func _buttons() -> Array:
	var s := _ui_scale
	var w := size.x
	var h := size.y
	var list: Array = []
	list.append({"id": "jump", "shape": "circle", "center": Vector2(w - 100 * s, h - 110 * s), "radius": 58 * s, "label": "ジャンプ"})
	list.append({"id": "run", "shape": "circle", "center": Vector2(w - 215 * s, h - 78 * s), "radius": 44 * s, "label": "走る"})
	var top_y := 14 * s
	var bw := 96 * s
	var bh := 44 * s
	var gap := 8 * s
	var labels := [["view", "視点"], ["debug", "調整"], ["world", "ワールド"]]
	for i in labels.size():
		var x: float = w - (bw + gap) * (labels.size() - i) - 6 * s
		list.append({"id": labels[i][0], "shape": "rect", "rect": Rect2(x, top_y, bw, bh), "label": labels[i][1]})
	return list


func _hit(b: Dictionary, pos: Vector2) -> bool:
	if b["shape"] == "circle":
		return pos.distance_to(b["center"]) <= b["radius"] * 1.15
	return (b["rect"] as Rect2).grow(6.0 * _ui_scale).has_point(pos)


func _draw() -> void:
	var s := _ui_scale
	var pressed_ids: Array = _button_of.values()
	for b in _buttons():
		var on: bool = pressed_ids.has(b["id"])
		var fill := Color(1, 1, 1, 0.26 if on else 0.13)
		var line := Color(1, 1, 1, 0.75 if on else 0.42)
		if b["shape"] == "circle":
			var c: Vector2 = b["center"]
			var r: float = b["radius"]
			draw_circle(c, r, fill)
			draw_arc(c, r, 0.0, TAU, 40, line, 2.0 * s, true)
			_label(b["label"], c, 18 * s)
		else:
			var rect: Rect2 = b["rect"]
			draw_rect(rect, fill, true)
			draw_rect(rect, line, false, 2.0 * s)
			_label(b["label"], rect.get_center(), 16 * s)

	# 仮想スティック（触れている間だけ出す）
	if _stick_index >= 0:
		var radius := Tuning.touch_stick_radius * s
		draw_arc(_stick_origin, radius, 0.0, TAU, 48, Color(1, 1, 1, 0.35), 2.0 * s, true)
		var knob := _stick_origin + (_stick_pos - _stick_origin).limit_length(radius)
		draw_circle(knob, radius * 0.42, Color(1, 1, 1, 0.3))
		draw_arc(knob, radius * 0.42, 0.0, TAU, 32, Color(1, 1, 1, 0.7), 2.0 * s, true)
	else:
		# 待機中はスティックの置き場所をうっすら示す
		var hint := Vector2(size.x * 0.17, size.y * 0.76)
		draw_arc(hint, Tuning.touch_stick_radius * s, 0.0, TAU, 48, Color(1, 1, 1, 0.12), 2.0 * s, true)
		_label("移動", hint, 16 * s, 0.35)


func _label(text: String, center: Vector2, font_size: float, alpha: float = 0.85) -> void:
	var size_px := int(font_size)
	var text_size: Vector2 = _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px)
	draw_string(_font, center - text_size * 0.5 + Vector2(0, text_size.y * 0.35), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, Color(1, 1, 1, alpha))
