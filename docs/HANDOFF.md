# HANDOFF.md — 引き継ぎメモ

最終更新: 2026-09-15（クラウドセッション）

## ブラウザで確認できる URL

- **https://axelrodichthys-blip.github.io/uchi-games/** （動作確認済み。main に push すると 1〜2 分で自動更新される）
  - 操作: **右ボタンを押しながらマウス**で視点（離すとマウスは自由）、Tab で視点をマウスに固定 / 解除、WASD で移動、Shift で走る、**Space でジャンプ**、ホイールで距離、V で一人称 / 三人称、F1 で調整パネル
  - コントローラー: 左スティック移動、右スティック視点、LB で走る、A でジャンプ、Start で視点切替
  - 出現地点の**右前 20m** に急斜面の山（約60度）。登ろうとすると滑り落ちる。登れない斜面は地面が茶色っぽく表示される
  - 出現地点の**左前 25m** に高さ 7m の台地（検証エリア）。開始地点側に 30° の登り坂、左側面に 42° の登り坂、奥側に 50° の下り坂（登れない・滑る）、右側面は崖
  - F1 の「体型」（body_scale / leg_length / arm_length / head_size / hat_size）と「動き」（anim_*）で仮キャラをその場で変えられる
  - スマホでは操作できません（キーボード / マウス / パッド前提）

## 今どこまで動くか

- フェーズ0 完了。フェーズ1 の実装は一通り入っている（ユーザーの操作感チェック待ち）
- `game/` を Godot 4.7.2 で headless 読み込み・起動できる（エラーなし）
- 起伏のある灰色のグリッド地面（ノイズ生成、出現地点の周り 15m は平ら）+ 目印の箱 + 急斜面テストの山
- 手足・コート付きの仮キャラ（黒い身体、サンドベージュの帽子と前が割れたコート）。`game/scenes/player/traveler.gd` が人体と同じ関節（骨盤・背骨・胸・首・頭 / 鎖骨・肩・肘・手首 / 股・膝・足首・つま先）で組み立て、足の位置から股と膝を IK で解く歩行（足が滑らない、踵接地→つま先で蹴る）、骨盤の上下・ひねり・傾きと胸の逆回転、頭の安定、走りの前傾と深い肘、ジャンプ・着地、待機の呼吸・体重移動・見回し、曲がるときの傾き。Mixamo の本アニメが入るまでのつなぎ
- Mixamo 用の A ポーズメッシュ `docs/reference/character/traveler_apose.obj`（Blender の bpy スクリプトで生成、Godot 用の .glb も `game/assets/`）と、FBX → .glb 変換スクリプト `tools/blender/mixamo_fbx_to_glb.py`（実物の FBX での検証はまだ）
- カメラ: 地形だけ避けて小物はすり抜け、間の小物は半透明（既定）。引き寄せ方式も F1 で選べる。寄るのは速く戻るのはゆっくり
- 三人称カメラ（右ボタン押下中にマウス / 右スティック、Tab で固定、ホイールで距離）、V で一人称
- WASD / 左スティック移動（2.8 m/s）、Shift / LB で走る（6.7 m/s）、Space / A でジャンプ（初速 5.9、約 1.8m）。空中でも少し操作できる（air_control）。フォグで地平線が霞む
- 斜面: 身体は垂直のまま。46 度より急な坂は滑り落ちる。下り坂は吸着して跳ねない
- F1 の調整パネル: 歩行速度・加速・カメラ距離・感度・視野角・フォグ濃度などをスライダーで変更、「値を書き出す」で現在値をテキスト表示
- クラウドでの確認手段が揃った:
  - `godot --headless --path game res://tools/walk_test.tscn` … 前進 / ジャンプ / 急斜面で滑る / 30° の坂を登る / 崖から落ちる / 50° を滑り降りる を検証（すべて OK）
  - `bash tools/screenshot.sh build/seq.png 100 walk 6 5` … 横から見た歩行を 6 コマ撮る（run / jump / idle も可）。Pillow で `build/sheet_*.png` にまとめて Claude が目で確認する
  - `bash tools/screenshot.sh build/shot.png 70 walk` … xvfb + Mesa のソフトウェア描画でスクリーンショット（3つ目の引数 walk / run / jump でその動きの途中を撮る）
  - `bash tools/export-web.sh` … Web 書き出し（build/web、約39MB）。headless Chromium で起動することも確認済み
- `.claude/settings.json` の SessionStart フックで `git pull --ff-only` が自動実行される（クラウド / Windows の Git Bash 共通。失敗時は解決せずメッセージを出すだけ）

## 未完了・詰まっている点

- リポジトリは Public 化済み、Pages は有効化済み（Source: GitHub Actions）。配置は成功している
- 作業は main に push 済み（ユーザーの許可を得て、ブランチ `claude/game-phase-0-to-1-69bbxr` から反映）
- Web ビルドの日本語フォント: VL Gothic を同梱した（同梱前はブラウザで日本語が□になっていた）
- 仮キャラのアニメは手続き（数式）。人体の関節と IK で「人形っぽさ」は減ったが、有名ゲームの動きはモーションキャプチャなので同じにはならない。本命は Mixamo（`docs/MIXAMO_GUIDE.md`、ユーザーのブラウザ操作が必要）
- `tools/blender/mixamo_fbx_to_glb.py` は Mixamo の実ファイルで未検証。FBX が届いたら直しながら使う
- その場で向きを変えるとき（振り向き）は足踏みをしていない（体だけ回る）。Mixamo の Turn アニメで解決予定
- Windows 側の Godot / Blender のパスは未設定

## 次にやること

1. ユーザーが Mixamo で仮キャラをリグしてアニメを落とす（`docs/MIXAMO_GUIDE.md`）→ Claude が .glb に変換して AnimationTree で組み込む。これが「動きの品質」の本命
2. 「歩く気持ちよさ」の初手: 足音、歩行時のカメラの微かな揺れ、加減速の味付け
3. 仮キャラの振り向き（足の踏み替え）。Mixamo が先に来るなら省略
4. ユーザーから詳細なキャラ設定とキャラ画像が届いたら、`tools/blender/` に bpy スクリプトを書いてモデル生成（要件は `docs/REFERENCE_GUIDE.md`）
5. 余裕があれば: 雨の景色のプロトタイプ用にワールドのテンプレート化を検討

## ユーザーにお願いすること（すべてブラウザで完結）

1. **Mixamo で仮キャラにアニメを付ける**（`docs/MIXAMO_GUIDE.md`。所要 20〜30 分、Adobe の無料アカウントが必要）。落とした FBX は GitHub の Add file → Upload files で `docs/reference/mixamo/` に置く
2. **詳細なキャラ設定を送る**（後日。`docs/REFERENCE_GUIDE.md` 1 章の「先に決めておくこと」も目を通してください）
3. **ChatGPT でキャラ画像を作る**（`docs/REFERENCE_GUIDE.md` 2〜3 章のプロンプト）。できた PNG は `docs/reference/character/` に置く
4. **決めてほしいこと**
   - 仮キャラの体型: F1 の body_scale / leg_length / arm_length / head_size / hat_size で良い値が見つかったら伝える
   - 一人称切替のキーは V でよい？

## 自宅PCでやること（ソフト導入が要るもの）

- Godot 4.7.2 をインストールし、`game/project.godot` を開いて実機で歩く。実行ファイルのパスを CLAUDE.md の「環境メモ」に書く
- Blender 4.x をインストールし、パスを CLAUDE.md に書く（フェーズ2 で bpy スクリプトを動かすため）
- Git for Windows（Git Bash）が入っていれば、SessionStart フック（`.claude/hooks/session-start.sh`）はそのまま動く

## ファイルの場所（今回追加したもの）

| 場所 | 内容 |
|---|---|
| `game/scripts/tuning.gd` | 操作感の数値（すべてここ） |
| `game/scenes/player/` | 操作（player.gd）、カメラ（camera_rig.gd）、仮キャラの組み立てと動き（traveler.gd） |
| `tools/blender/` | Mixamo 用メッシュの生成（build_traveler_apose.py）、FBX → glb 変換（mixamo_fbx_to_glb.py） |
| `docs/MIXAMO_GUIDE.md` / `docs/REFERENCE_GUIDE.md` | Mixamo の手順 / キャラ画像とワールド資料の要件 |
| `game/scenes/worlds/gray/` | 灰色の世界（地面・箱・フォグ） |
| `game/scenes/ui/` | 操作案内の HUD と F1 調整パネル |
| `game/shaders/grid_ground.gdshader` | 地面のグリッド |
| `game/tools/` | headless テスト・スクリーンショット用のシーン |
| `game/export_presets.cfg` | Web 書き出し設定（スレッド無効） |
| `tools/cloud-setup.sh` | クラウド環境に Godot / Blender を導入 |
| `tools/export-web.sh` / `tools/screenshot.sh` | Web 書き出し / スクリーンショット |
| `.github/workflows/deploy-pages.yml` | main への push で Pages に自動配置 |
| `.claude/settings.json` / `.claude/hooks/session-start.sh` | セッション開始時の git pull |
