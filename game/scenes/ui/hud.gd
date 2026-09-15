extends CanvasLayer
## 操作の案内。マウスを掴んでいる間は薄くする。

@onready var label: Label = $Margin/Label

const TEXT_IDLE := "右ボタンを押しながらマウス: 視点   Tab: 視点をマウスに固定 / 解除\nWASD / 左スティック: 移動   Shift: 走る   Space: ジャンプ   右スティック: 視点\nホイール: 距離   V: 一人称 / 三人称   F1: 調整パネル"
const TEXT_ACTIVE := "Tab / Esc: マウスを自由にする   V: 視点切替   F1: 調整"


func _process(_delta: float) -> void:
	var captured := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	label.text = TEXT_ACTIVE if captured else TEXT_IDLE
	label.modulate.a = 0.5 if captured else 1.0
