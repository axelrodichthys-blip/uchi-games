extends CanvasLayer
## 操作の案内。マウスを掴んでいる間は薄くする。

@onready var label: Label = $Margin/Label

const TEXT_IDLE := "右ボタンを押しながらマウス: 視点   Tab: 視点をマウスに固定 / 解除\nWASD / 左スティック: 移動   Shift: 走る   Space: ジャンプ   右スティック: 視点\nホイール: 距離   V: 一人称 / 三人称   F1: 調整パネル   F2: 次のワールド"
const TEXT_ACTIVE := "Tab / Esc: マウスを自由にする   V: 視点切替   F1: 調整   F2: 次のワールド"
const TEXT_TOUCH := "左半分: 指をすべらせて移動   右半分: なぞって視点\n右下: ジャンプ / 走る   右上: 視点 / 調整 / ワールド"

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
		label.text = TEXT_TOUCH + _hint
		label.modulate.a = 0.75
		return
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	label.text = (TEXT_ACTIVE if captured else TEXT_IDLE) + _hint
	label.modulate.a = 0.5 if captured else 1.0
