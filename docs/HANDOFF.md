# HANDOFF.md — 引き継ぎメモ

最終更新: 2026-09-16（クラウドセッション）

## ブラウザで確認できる URL

- **https://axelrodichthys-blip.github.io/uchi-games/** （main に push すると 1〜2 分で自動更新される）
  - 起動すると **「雨の景色」** から始まる。**F2** で「灰色の世界（検証用）」と切り替え
  - 操作: **右ボタンを押しながらマウス**で視点（離すとマウスは自由）、Tab で視点をマウスに固定 / 解除、WASD で移動、Shift で走る、Space でジャンプ、ホイールで距離、V で一人称 / 三人称、F1 で調整パネル
  - コントローラー: 左スティック移動、右スティック視点、LB で走る、A でジャンプ、Start で視点切替
  - 雨の景色: 正面（-Z）の遠く約 140m に灯りがあり、飛び石の道が続く。雨音・足音が鳴る（ブラウザは最初のクリックまで音が出ない）
  - 灰色の世界: 出現地点の右前に 60° の山、左前に台地（30° / 42° の登り坂、50° の下り坂、崖）
  - スマホでは操作できません（キーボード / マウス / パッド前提）

## 今回（2026-09-16）やったこと

1. **キャラの向きの修正**: Mixamo のモデルは +Z が正面だったため、進行方向と逆を向いていた。`traveler_rig.gd` で 180° 回して解決
2. **ジャンプの整理**: 踏切で腕を大きく広げる部分と着地の深いしゃがみ、空中クリップに入っていた「腰が浮く」移動を除去。空中区間を 0.35 倍速で滞空全体に使い、落下ポーズは 1 秒以上落ちるときだけ。着地は落下速度で軽い / 強いを切替
3. **足の滑りの原因**: 歩き・走りクリップの基準速度の計測が間違っていた（走りは 2.4 → 実測 3.6 m/s）。`inspect_glb.gd` を固定刻み・向き基準で測るよう直し、`tuning.gd` の初期値を更新
4. **雨の景色のプロトタイプ**（`game/scenes/worlds/rain/`）: 灰色の空、フォグ、雨粒、濡れた地面と水たまりの映り込み・波紋（`shaders/wet_ground.gdshader`）、式で生成した雨音、遠くの灯りと飛び石
5. **ワールドのテンプレート化**: `scenes/worlds/world_base.gd`（`WorldBase`）に地形・フォグ・F2 切替・小物ヘルパーを共通化。作り方は `scenes/worlds/README.md`
6. **歩く気持ちよさの初手**: 足音（アニメの足首の骨が地面に着いた瞬間に鳴らす。濡れた地面は「ぴちゃ」）、歩行時のカメラの微かな揺れ、走行時に視野角を少し広げる。F1 の camera_bob / run_fov_boost / footstep_volume_db / ambient_volume_db で調整
7. **地面が消える不具合の修正**: 地形メッシュの三角形の並びが裏向きで、この日のクラウド環境（Mesa）では地面が描かれなかった。並びを反転（法線が上向きになり、照明的にも正しい）
8. **ルール追加**（CLAUDE.md）: 報告前に自分でテストプレイし、合格点になるまで検証と修正を繰り返してから見せる

## 今どこまで動くか

- `godot --headless --path game res://tools/walk_test.tscn` … 前進 / ジャンプ / 急斜面 / 30° の坂 / 崖 / 50° の下り坂 / 足音の回数、すべて OK
- スクリーンショット（xvfb + Mesa）で確認済み: 歩き・走りがキャラの向きと一致、ジャンプの一連、雨の景色の全景と足元（水たまり・波紋・影）、灰色の世界
- Web 書き出し（`bash tools/export-web.sh`、約 42MB）を headless Chromium（`bash tools/web-check.sh`）で読み込み確認（JS のエラーなし、起動画面まで。ソフトウェア描画ではシーンの描画まで進まないので、実際の画面は Pages でユーザーが確認する）
- クラウドの確認手段（追加分）:
  - `bash tools/clip-view.sh build/c Jump 0.0,0.3,0.6` … アニメクリップ単体のポーズを PNG に
  - `python3 tools/sheet.py build/c build/sheet.png` … 連番 PNG を 1 枚に並べる（Pillow: `pip install pillow`）
  - `bash tools/screenshot.sh build/x.png 90 hop 12 7` … その場ジャンプの連続コマ、`idle` は足元を見下ろす
  - `WORLD=res://scenes/worlds/gray/gray_world.tscn bash tools/screenshot.sh ...` … ワールド指定

## 未完了・詰まっている点

- ジャンプの滞空中、Mixamo のクリップの都合で頭を下げて下を見る。小さいジャンプでは少し大げさに見えるかもしれない（クリップ差し替えか、頭の骨だけ上書きする対処が候補）
- 水たまりの映り込みは Compatibility レンダラーでは弱いので、式で空の色を足している。実機でどう見えるかは未確認
- 雨粒は CPUParticles3D 1400 個。内蔵 GPU でのフレームレートは未確認（重ければ amount を減らす）
- 音はすべて式で生成した仮のもの。雨音・足音の質は要改善
- 灯りに着いたときに何も起きない
- 数式の仮キャラ（F1 の character_model = 1）は足音を出さない（比較用なので保留）
- Windows 側の Godot / Blender のパスは未設定

## 次にやること

1. ユーザーの感想を受けて: 向き・ジャンプ・足の滑りが直ったか、雨の景色の第一印象（暗さ、雨の量、音）
2. 雨の景色を詰める: 色味・水たまりの量（`wet_ground.gdshader` の puddle_amount）・雨の量・灯りに着いたときの演出（雨が弱まる、音が変わる、など）
3. ジャンプ滞空中の頭の向きの改善
4. 本キャラのデザインが届いたら、`build_traveler_apose.py` を本キャラの形に書き換えて同じ手順で差し替え
5. 2 つ目のワールド（`scenes/worlds/README.md` の手順で rain を複製）

## ユーザーにお願いすること（すべてブラウザで完結）

1. **ブラウザで歩いて感想を送る**: 歩き・走り・ジャンプの動き、足音、カメラの揺れ（気持ち悪ければ F1 で camera_bob を 0 に）、雨の景色の印象
2. **詳細なキャラ設定を送る**（後日。`docs/REFERENCE_GUIDE.md` 1 章）
3. **ChatGPT でキャラ画像を作る**（`docs/REFERENCE_GUIDE.md` 2〜3 章）。できた PNG は `docs/reference/character/` に置く
4. **決めてほしいこと**
   - 雨の景色の「見つけるもの」は「遠くの灯り」でよいか。着いたときに何が起きてほしいか
   - 一人称切替のキーは V でよい？

## 自宅PCでやること（ソフト導入が要るもの）

- Godot 4.7.2 をインストールし、`game/project.godot` を開いて実機で歩く。実行ファイルのパスを CLAUDE.md の「環境メモ」に書く
- Blender 4.x をインストールし、パスを CLAUDE.md に書く（フェーズ2 で bpy スクリプトを動かすため）
- 内蔵 GPU で雨の景色のフレームレートを見る（F1 に FPS 表示あり）

## ファイルの場所（今回追加・変更したもの）

| 場所 | 内容 |
|---|---|
| `game/scenes/worlds/world_base.gd` | ワールド共通の土台（地形・フォグ・F2 切替・小物ヘルパー） |
| `game/scenes/worlds/README.md` | 新しいワールドの作り方 |
| `game/scenes/worlds/rain/` | 雨の景色（rain_world.gd / .tscn） |
| `game/shaders/wet_ground.gdshader` | 濡れた地面・水たまり・波紋 |
| `game/scripts/worlds.gd` | ワールド一覧（F2 の巡回順） |
| `game/scenes/player/footsteps.gd` | 足音の再生 |
| `game/scenes/player/traveler_rig.gd` | 向きの補正、空中クリップの補正、ジャンプ状態機械、足音の検出 |
| `game/scenes/player/camera_rig.gd` | 歩行の揺れ、走行時の視野角 |
| `game/assets/audio/` | 雨音・足音（式で生成。`tools/make_rain_sound.py` / `tools/make_footstep_sounds.py`） |
| `game/tools/clip_view.gd` / `tools/clip-view.sh` | アニメクリップの時刻指定描画 |
| `tools/sheet.py` | 連番 PNG を 1 枚に |
| `tools/web-check.sh` | Web 書き出しを headless Chromium で起動確認 |
| `game/scripts/tuning.gd` | camera_bob / run_fov_boost / footstep_volume_db / ambient_volume_db と歩き・走りの基準速度 |
