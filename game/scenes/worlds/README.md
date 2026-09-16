# ワールドの作り方（テンプレート）

ワールドは `scenes/worlds/<name>/` に 1 ディレクトリ。共通の土台は `scenes/worlds/world_base.gd`（`WorldBase`）。
一番小さな見本は `rain/`（雨の景色）。**新しいワールドは rain をコピーして始める。**

## 手順

1. `scenes/worlds/rain/` を `scenes/worlds/<name>/` にコピーし、`rain_world.gd` / `rain_world.tscn` を `<name>_world.*` に改名
2. `.tscn` の先頭 `uid="uid://..."` を別の文字列に変える（重複すると Godot が警告する）
3. `.tscn` のルートノード名と `script` のパス、`ext_resource` のパスを直す
4. `scripts/worlds.gd` の `WORLDS` に 1 行足す（F2 で巡回できるようになる）
5. 見た目を決める:
   - **空と光**: `WorldEnvironment` の Environment（背景 = 単色 or ProceduralSky、環境光、フォグ色、トーンマップ）と `DirectionalLight3D`
   - **地面**: `Terrain/MeshInstance3D` の `material_override`。式で描くシェーダーを `shaders/` に置く（雨は `wet_ground.gdshader`、灰色は `grid_ground.gdshader`）
   - **地形の起伏**: ルートノードの `hill_height` / `hill_frequency` / `flat_radius` / `terrain_seed`。式を変えたいときは `_terrain_height(x, z)` を上書き
   - **フォグの初期値**: `fog_density_default`（F1 で変えられる。ワールドに入るたびに戻る）
6. 小物は `_decorate()` に書く。`add_static_box()` / `add_static_mesh()` で置ける（`layer` 1 = 地形扱いでカメラが避ける、4 = 小物でカメラがすり抜けて透過）
7. `hud_hint` に、そのワールドで「見つけるもの」のヒントを一言
8. 確認: `bash tools/screenshot.sh build/<name>.png 90` と `WORLD=res://scenes/worlds/<name>/<name>_world.tscn bash tools/screenshot.sh build/<name>_ground.png 90 idle`

## 自動でついてくるもの（`WorldBase` が用意する。特に何もしなくてよい）

- **世界の端**: 地形が端に向かって山並みのように盛り上がり、登れない斜面になる。その中に見えない壁、さらに落ちたら出現地点に戻す保険。強さは `rim_width` / `rim_height` / `rim_variation` / `boundary_inset` / `fall_limit` で調整
- **F2 でのワールド巡回**と、フェードつきの移動 `go_to_world(シーンのパス, 色, 秒)`。移動を始めると `world_changing` シグナルが出る
- **フォグの濃さ**を F1 から反映（初期値は `fog_density_default`）
- **足音の組**（`footstep_set` に "stone" / "wet"）

## 決めごと

- 色はワールドごとに 3〜5 色。GAME_DESIGN.md の 5 章の表に書く
- 音は `assets/audio/` に置く。外部素材を使わず式で作る場合は `tools/make_rain_sound.py` を見本にする
- 地形は 200〜500m 四方。遠くはフォグで消す（`terrain_size` を大きくして「広さ」を作らない）
- 「見つけるもの」を 1 つ置き、そこへ視線が向く導線（道、灯り、音）を作る
