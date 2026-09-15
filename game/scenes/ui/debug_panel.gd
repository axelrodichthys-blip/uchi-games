extends CanvasLayer
## F1 で開く調整パネル。Tuning の数値をスライダーでその場で変えられる。
## 「値をコピー」で現在値をコンソールと下のテキスト欄に出す。次のセッションで Claude に伝える。

@onready var panel: PanelContainer = $Panel
@onready var rows: VBoxContainer = $Panel/Scroll/VBox/Rows
@onready var dump_edit: TextEdit = $Panel/Scroll/VBox/DumpEdit
@onready var fps_label: Label = $Panel/Scroll/VBox/FpsLabel

var _sliders: Dictionary = {}


func _ready() -> void:
	panel.visible = false
	_build_rows()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		panel.visible = not panel.visible
		if panel.visible:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
			_refresh()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if panel.visible:
		fps_label.text = "FPS: %d" % Engine.get_frames_per_second()
		# ホイールなどで外から変わった値をスライダーに反映
		for key in _sliders.keys():
			var slider: HSlider = _sliders[key]["slider"]
			if not slider.has_focus() and not is_equal_approx(slider.value, Tuning.get(key)):
				slider.set_value_no_signal(Tuning.get(key))
				_sliders[key]["value"].text = _fmt(Tuning.get(key))


func _build_rows() -> void:
	for key in Tuning.RANGES.keys():
		var range_info: Array = Tuning.RANGES[key]
		var row := HBoxContainer.new()
		var name_label := Label.new()
		name_label.text = key
		name_label.custom_minimum_size.x = 170
		var slider := HSlider.new()
		slider.min_value = range_info[0]
		slider.max_value = range_info[1]
		slider.step = range_info[2]
		slider.value = Tuning.get(key)
		slider.custom_minimum_size.x = 220
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var value_label := Label.new()
		value_label.custom_minimum_size.x = 60
		value_label.text = _fmt(Tuning.get(key))
		slider.value_changed.connect(func(v: float) -> void:
			Tuning.set(key, v)
			value_label.text = _fmt(v)
		)
		row.add_child(name_label)
		row.add_child(slider)
		row.add_child(value_label)
		rows.add_child(row)
		_sliders[key] = {"slider": slider, "value": value_label}

	var invert := CheckBox.new()
	invert.text = "invert_y（上下反転）"
	invert.button_pressed = Tuning.invert_y
	invert.toggled.connect(func(on: bool) -> void: Tuning.invert_y = on)
	rows.add_child(invert)

	var copy_button := Button.new()
	copy_button.text = "値を書き出す（下の欄とコンソールに出ます）"
	copy_button.pressed.connect(_refresh_dump)
	rows.add_child(copy_button)


func _refresh() -> void:
	_refresh_dump()


func _refresh_dump() -> void:
	var text := Tuning.dump()
	dump_edit.text = text
	print("---- Tuning ----\n" + text)


func _fmt(v: float) -> String:
	return "%.3f" % v if absf(v) < 1.0 else "%.2f" % v
