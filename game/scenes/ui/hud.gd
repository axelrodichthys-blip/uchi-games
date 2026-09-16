extends CanvasLayer
## 操作の案内。マウスを掴んでいる間は薄くする。

@onready var margin: MarginContainer = $Margin
@onready var label: Label = $Margin/Label

const TEXT_IDLE := "右ボタンを押しながらマウス: 視点   Tab: 視点をマウスに固定 / 解除\nWASD / 左スティック: 移動   Shift: 走る   Space: ジャンプ   右スティック: 視点\nホイール: 距離   V: 一人称 / 三人称   F1: 調整パネル   F2: 次のワールド"
const TEXT_ACTIVE := "Tab / Esc: マウスを自由にする   V: 視点切替   F1: 調整   F2: 次のワールド"

var _hint: String = ""


func _ready() -> void:
	var world := get_parent()
	if world is WorldBase:
		var world_name: String = WorldList.name_of(world.scene_file_path)
		_hint = "\n" + world_name
		if world.hud_hint != "":
			_hint += "   " + world.hud_hint


## タッチ操作が出ているか（出ていればキーボードの案内は邪魔なので差し替える）
func _touch_visible() -> bool:
	var world := get_parent()
	if world == null:
		return false
	var node := world.get_node_or_null("TouchControls/TouchUI")
	return node != null and node.visible


func _process(_delta: float) -> void:
	if _touch_visible():
		# スマホでは画面が狭いので、操作の説明はボタンの絵に任せ、ワールドの案内だけ出す。
		# 右上のボタンの下に置いて重ならないようにする
		label.text = _hint.strip_edges()
		label.modulate.a = 0.8
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var unit := minf(get_viewport().get_visible_rect().size.x, get_viewport().get_visible_rect().size.y)
		margin.offset_top = unit * 0.15   # 右上のボタンの下に置く（重ならないように）
		label.add_theme_font_size_override("font_size", maxi(int(unit * 0.030), 12))
		return
	label.remove_theme_font_size_override("font_size")
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	margin.offset_top = 0.0
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	label.text = (TEXT_ACTIVE if captured else TEXT_IDLE) + _hint
	label.modulate.a = 0.5 if captured else 1.0
