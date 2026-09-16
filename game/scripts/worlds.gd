class_name WorldList
## ワールドの一覧。F2 で次のワールドへ切り替える（world_base.gd から使う）。
## 新しいワールドを作ったらここに 1 行足す。先頭が起動時のワールド（project.godot の main_scene と合わせる）。

const WORLDS := [
	{"name": "雨の景色", "scene": "res://scenes/worlds/rain/rain_world.tscn"},
	{"name": "灰色の世界（検証用）", "scene": "res://scenes/worlds/gray/gray_world.tscn"},
]


static func next_scene(current: String) -> String:
	for i in WORLDS.size():
		if WORLDS[i]["scene"] == current:
			return WORLDS[(i + 1) % WORLDS.size()]["scene"]
	return WORLDS[0]["scene"]


static func name_of(scene: String) -> String:
	for w in WORLDS:
		if w["scene"] == scene:
			return w["name"]
	return scene.get_file().get_basename()
