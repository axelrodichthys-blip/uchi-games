extends Node
## 操作感に関わる数値はすべてここにまとめる（散らばらせない）。
## F1 のデバッグパネルから、その場で変更して試せる。
## 良い数値が見つかったら、この初期値を書き換える。

# ---- 移動 ----
var walk_speed: float = 2.5        # 歩く速さ m/s（目安 2〜3）
var run_speed: float = 5.0         # 走る速さ m/s
var acceleration: float = 10.0     # 加速の速さ（大きいほどキビキビ）
var deceleration: float = 14.0     # 止まる速さ
var turn_speed: float = 10.0       # キャラが進行方向を向く速さ
var gravity: float = 9.8
var jump_velocity: float = 4.5     # ジャンプの初速 m/s（4.5 で約 1m の高さ）
var slope_max_angle: float = 46.0  # これより急な斜面は「壁」扱いで登れず滑る（度）
var floor_snap: float = 0.5        # 下り坂で足を地面に吸着させる距離 m（跳ねなくなる）

# ---- カメラ（三人称）----
var camera_distance: float = 4.0   # キャラからカメラまでの距離 m
var camera_distance_min: float = 1.5
var camera_distance_max: float = 10.0
var camera_zoom_step: float = 0.5  # ホイール1目盛りで変わる距離
var camera_height: float = 1.4     # 注視点の高さ（キャラの足元から）
var camera_follow_speed: float = 10.0  # 距離変化・視点切替の滑らかさ
var camera_pitch_default: float = -15.0  # 起動時の見下ろし角度（度）
var pitch_min: float = -70.0       # 見下ろせる限界（度）
var pitch_max: float = 60.0        # 見上げられる限界（度）
var fov: float = 70.0              # 視野角（三人称）
var fov_first_person: float = 80.0 # 視野角（一人称）
var first_person_eye_height: float = 1.55

# ---- 入力 ----
var mouse_sensitivity: float = 0.15   # 度 / ピクセル
var stick_sensitivity: float = 150.0  # 度 / 秒（右スティック）
var invert_y: bool = false

# ---- 風景 ----
var fog_density: float = 0.012     # フォグの濃さ（大きいほど近くまで霞む）

# デバッグパネル用: 変数名 -> [最小, 最大, 刻み]
const RANGES := {
	"walk_speed": [0.5, 8.0, 0.1],
	"run_speed": [1.0, 15.0, 0.1],
	"acceleration": [1.0, 40.0, 0.5],
	"deceleration": [1.0, 40.0, 0.5],
	"turn_speed": [1.0, 30.0, 0.5],
	"jump_velocity": [2.0, 10.0, 0.1],
	"slope_max_angle": [20.0, 80.0, 1.0],
	"camera_distance": [1.5, 10.0, 0.1],
	"camera_height": [0.5, 3.0, 0.05],
	"camera_follow_speed": [1.0, 30.0, 0.5],
	"pitch_min": [-89.0, 0.0, 1.0],
	"pitch_max": [0.0, 89.0, 1.0],
	"fov": [40.0, 110.0, 1.0],
	"fov_first_person": [40.0, 110.0, 1.0],
	"mouse_sensitivity": [0.02, 0.6, 0.01],
	"stick_sensitivity": [30.0, 400.0, 5.0],
	"fog_density": [0.0, 0.08, 0.001],
}


## 現在の値を「設定ファイルに貼れる形」で返す（デバッグパネルのコピー用）
func dump() -> String:
	var lines := PackedStringArray()
	for key in RANGES.keys():
		lines.append("%s = %s" % [key, str(get(key))])
	lines.append("invert_y = %s" % str(invert_y))
	return "\n".join(lines)
