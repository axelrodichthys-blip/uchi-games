extends Node
## メインシーンを読み込んで数フレーム描画し、PNG を保存して終了する。
## 使い方（tools/screenshot.sh から呼ぶ）:
##   godot --path game res://tools/screenshot_runner.tscn -- out.png [frames]

const DEFAULT_OUT := "screenshot.png"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var out_path: String = args[0] if args.size() > 0 else DEFAULT_OUT
	var frames: int = int(args[1]) if args.size() > 1 else 30
	var main_scene: String = ProjectSettings.get_setting("application/run/main_scene")
	var packed: PackedScene = load(main_scene)
	get_tree().root.add_child.call_deferred(packed.instantiate())
	for i in frames:
		await get_tree().process_frame
	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out_path)
	if err == OK:
		print("[screenshot] 保存しました: %s (%dx%d)" % [out_path, image.get_width(), image.get_height()])
	else:
		push_error("[screenshot] 保存に失敗: %s (err=%d)" % [out_path, err])
	get_tree().quit(0 if err == OK else 1)
