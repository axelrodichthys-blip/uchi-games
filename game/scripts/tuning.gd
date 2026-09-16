extends Node
## 操作感に関わる数値はすべてここにまとめる（散らばらせない）。
## F1 のデバッグパネルから、その場で変更して試せる。
## 良い数値が見つかったら、この初期値を書き換える。

# ---- 移動 ----
var walk_speed: float = 2.8        # 歩く速さ m/s（目安 2〜3）
var run_speed: float = 6.7         # 走る速さ m/s
var acceleration: float = 10.0     # 加速の速さ（大きいほどキビキビ）
var deceleration: float = 14.0     # 止まる速さ
var turn_speed: float = 10.0       # キャラが進行方向を向く速さ
var gravity: float = 9.8
var jump_velocity: float = 5.9     # ジャンプの初速 m/s（5.9 で約 1.8m の高さ）
var slope_max_angle: float = 46.0  # これより急な斜面は「壁」扱いで登れず滑る（度）
var air_control: float = 0.3       # 空中での操作の効き（0 で効かない、1 で地上と同じ）
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
var camera_collision_mode: int = 0  # 0=すり抜けて小物を透過 / 1=引き寄せ（OPTIONS 参照）
var camera_pull_in_speed: float = 20.0   # 物にぶつかって寄るときの速さ
var camera_pull_out_speed: float = 4.0   # 元の距離に戻るときの速さ（ゆっくり）
var occluder_fade: float = 0.75          # 間にある小物の透け具合（0 で透過しない、1 で消える）

# ---- 歩く気持ちよさ ----
var camera_bob: float = 0.02          # 歩行時のカメラの上下の揺れ m（0 で無し。走ると 1.6 倍まで増える）
var run_fov_boost: float = 6.0        # 走っているとき視野角を広げる量（度。速さの実感用）
var footstep_volume_db: float = -8.0  # 足音の音量 dB
var ambient_volume_db: float = -14.0  # 環境音（雨音など）の音量 dB

# ---- 入力 ----
var mouse_sensitivity: float = 0.15   # 度 / ピクセル
var stick_sensitivity: float = 150.0  # 度 / 秒（右スティック）
var invert_y: bool = false

# ---- キャラのモデル ----
var character_model: int = 0          # 0=Mixamo アニメ / 1=数式の仮キャラ（OPTIONS 参照）
var anim_walk_native_speed: float = 1.35  # Walking クリップが想定している移動速度 m/s（tools/inspect_glb.gd で計測。足が滑るなら調整）
var anim_run_native_speed: float = 3.6    # Running クリップが想定している移動速度 m/s（計測値）
var arm_swing: int = 0                    # 0=歩き・走りで腕を振らない（待機の腕） / 1=クリップ通りに振る（OPTIONS 参照）

# ---- 仮キャラの体型（倍率。1.0 が基準）----
var body_scale: float = 1.0
var leg_length: float = 1.0
var arm_length: float = 1.0
var head_size: float = 1.0
var hat_size: float = 1.0

# ---- 仮キャラの動き ----
var anim_stride_walk: float = 0.62   # 歩きの1歩の長さ m
var anim_stride_run: float = 1.05    # 走りの1歩の長さ m
var anim_arm_swing: float = 1.0      # 腕の振りの倍率
var anim_bounce: float = 1.0         # 上下動の倍率
var anim_lean_run: float = 12.0      # 走りの前傾（度）

# ---- 風景 ----
var fog_density: float = 0.012     # フォグの濃さ（大きいほど近くまで霞む）
var rain_amount: float = 0.6       # 雨の量 0〜1（雨の景色）
var puddle_amount: float = 0.42    # 水たまりの量 0〜0.9（雨の景色）
var puddle_size: float = 14.0      # 水たまりの大きさの目安 m（雨の景色）

# デバッグパネル用: 変数名 -> [最小, 最大, 刻み]
const RANGES := {
	"walk_speed": [0.5, 8.0, 0.1],
	"run_speed": [1.0, 15.0, 0.1],
	"acceleration": [1.0, 40.0, 0.5],
	"deceleration": [1.0, 40.0, 0.5],
	"turn_speed": [1.0, 30.0, 0.5],
	"jump_velocity": [2.0, 10.0, 0.1],
	"slope_max_angle": [20.0, 80.0, 1.0],
	"air_control": [0.0, 1.0, 0.05],
	"camera_distance": [1.5, 10.0, 0.1],
	"camera_height": [0.5, 3.0, 0.05],
	"camera_follow_speed": [1.0, 30.0, 0.5],
	"pitch_min": [-89.0, 0.0, 1.0],
	"pitch_max": [0.0, 89.0, 1.0],
	"fov": [40.0, 110.0, 1.0],
	"fov_first_person": [40.0, 110.0, 1.0],
	"mouse_sensitivity": [0.02, 0.6, 0.01],
	"stick_sensitivity": [30.0, 400.0, 5.0],
	"camera_pull_in_speed": [2.0, 40.0, 1.0],
	"camera_pull_out_speed": [0.5, 20.0, 0.5],
	"occluder_fade": [0.0, 1.0, 0.05],
	"fog_density": [0.0, 0.08, 0.001],
	"rain_amount": [0.0, 1.0, 0.05],
	"puddle_amount": [0.0, 0.9, 0.02],
	"puddle_size": [3.0, 60.0, 1.0],
	"camera_bob": [0.0, 0.1, 0.005],
	"run_fov_boost": [0.0, 20.0, 0.5],
	"footstep_volume_db": [-40.0, 6.0, 1.0],
	"ambient_volume_db": [-40.0, 0.0, 1.0],
	"anim_walk_native_speed": [0.5, 4.0, 0.05],
	"anim_run_native_speed": [1.5, 8.0, 0.05],
	"body_scale": [0.7, 1.4, 0.01],
	"leg_length": [0.7, 1.4, 0.01],
	"arm_length": [0.7, 1.4, 0.01],
	"head_size": [0.7, 1.4, 0.01],
	"hat_size": [0.6, 1.6, 0.01],
	"anim_stride_walk": [0.4, 0.9, 0.01],
	"anim_stride_run": [0.7, 1.5, 0.01],
	"anim_arm_swing": [0.0, 2.0, 0.05],
	"anim_bounce": [0.0, 2.0, 0.05],
	"anim_lean_run": [0.0, 25.0, 0.5],
}

# デバッグパネル用: 選択式の設定。変数名 -> 選択肢の名前（値はその index）
const OPTIONS := {
	"character_model": ["Mixamo のアニメ（本命）", "数式の仮キャラ（比較用）"],
	"arm_swing": ["歩き・走りで腕を振らない（待機の腕）", "クリップ通りに振る"],
	"camera_collision_mode": ["すり抜けて小物を透過", "引き寄せ（地形・小物を避ける）"],
}


## 現在の値を「設定ファイルに貼れる形」で返す（デバッグパネルのコピー用）
func dump() -> String:
	var lines := PackedStringArray()
	for key in RANGES.keys():
		lines.append("%s = %s" % [key, str(get(key))])
	for key in OPTIONS.keys():
		lines.append("%s = %d" % [key, get(key)])
	lines.append("invert_y = %s" % str(invert_y))
	return "\n".join(lines)
