extends AudioStreamPlayer
## 足音を鳴らす。音源は式で生成した短い WAV（tools/make_footstep_sounds.py）。
## ワールドの footstep_set（"stone" / "wet"）で音の組を選ぶ。毎回ランダムに 1 つ選び、ピッチを少し揺らす。
## AnimationTree 側（traveler_rig.gd）の footstep シグナルから呼ばれる。

const SETS := {
	"stone": ["res://assets/audio/step_stone_1.wav", "res://assets/audio/step_stone_2.wav", "res://assets/audio/step_stone_3.wav"],
	"wet": ["res://assets/audio/step_wet_1.wav", "res://assets/audio/step_wet_2.wav", "res://assets/audio/step_wet_3.wav"],
}

var _streams: Array[AudioStream] = []
var _last: int = -1
var _rng := RandomNumberGenerator.new()
# 同時に 2 音まで重ねられるように、予備のプレイヤーを 1 つ持つ
var _second: AudioStreamPlayer


func _ready() -> void:
	_second = AudioStreamPlayer.new()
	_second.bus = bus
	add_child(_second)
	set_surface("stone")


func set_surface(surface: String) -> void:
	_streams.clear()
	for path in SETS.get(surface, SETS["stone"]):
		var stream: AudioStream = load(path)
		if stream:
			_streams.append(stream)


func on_step(_side: int, strength: float) -> void:
	if _streams.is_empty():
		return
	var i := _rng.randi_range(0, _streams.size() - 1)
	if i == _last and _streams.size() > 1:
		i = (i + 1) % _streams.size()
	_last = i
	var target: AudioStreamPlayer = self if not playing else _second
	target.stream = _streams[i]
	target.pitch_scale = _rng.randf_range(0.92, 1.08)
	target.volume_db = Tuning.footstep_volume_db + linear_to_db(clampf(0.4 + 0.6 * strength, 0.05, 1.0))
	target.play()
