# HANDOFF.md — 引き継ぎメモ

最終更新: 2026-09-15（クラウドセッション）

## ブラウザで確認できる URL

- **https://axelrodichthys-blip.github.io/uchi-games/** （動作確認済み。main に push すると 1〜2 分で自動更新される）
  - 操作: 画面をクリック → WASD で移動、マウスで視点、Shift で走る、ホイールで距離、V で一人称 / 三人称、F1 で調整パネル、Esc でマウス解放
  - コントローラー: 左スティック移動、右スティック視点、LB で走る、Start で視点切替
  - スマホでは操作できません（キーボード / マウス / パッド前提）

## 今どこまで動くか

- フェーズ0 完了。フェーズ1 の実装は一通り入っている（ユーザーの操作感チェック待ち）
- `game/` を Godot 4.7.2 で headless 読み込み・起動できる（エラーなし）
- 灰色のグリッド地面 + 目印の箱 + 黒いカプセル仮キャラ（とんがり帽子・白い目つき）
- 三人称カメラ（マウス / 右スティック、ホイールで距離、SpringArm で壁に埋まらない）、V で一人称
- WASD / 左スティック移動、Shift / LB で走る。フォグで地平線が霞む
- F1 の調整パネル: 歩行速度・加速・カメラ距離・感度・視野角・フォグ濃度などをスライダーで変更、「値を書き出す」で現在値をテキスト表示
- クラウドでの確認手段が揃った:
  - `godot --headless --path game res://tools/walk_test.tscn` … 1秒前進して移動量を検証（OK: 2.17 m/s）
  - `bash tools/screenshot.sh build/shot.png` … xvfb + Mesa のソフトウェア描画でスクリーンショット（動いた）
  - `bash tools/export-web.sh` … Web 書き出し（build/web、約39MB）。headless Chromium で起動することも確認済み
- `.claude/settings.json` の SessionStart フックで `git pull --ff-only` が自動実行される（クラウド / Windows の Git Bash 共通。失敗時は解決せずメッセージを出すだけ）

## 未完了・詰まっている点

- リポジトリは Public 化済み、Pages は有効化済み（Source: GitHub Actions）。配置は成功している
- 作業は main に push 済み（ユーザーの許可を得て、ブランチ `claude/game-phase-0-to-1-69bbxr` から反映）
- Web ビルドの日本語フォント: VL Gothic を同梱した（同梱前はブラウザで日本語が□になっていた）
- 操作感の数値はすべて初期値のまま（ユーザーの感想待ち）
- Windows 側の Godot / Blender のパスは未設定

## 次にやること

1. ユーザーがブラウザで歩き、操作感の感想をもらう（速さ・カメラ距離・感度・視野角）。F1 パネルで見つけた値を `game/scripts/tuning.gd` の初期値に反映する
2. ジャンプを入れる（決定済み）。仮キャラのうちに入力・重力・着地の手触りを作る
3. 「歩く気持ちよさ」の初手: 足音、歩行時のカメラの微かな揺れ、加減速の味付け
4. ユーザーから詳細なキャラ設定とキャラ画像が届いたら、`tools/blender/` に bpy スクリプトを書いてモデル生成（要件は `docs/REFERENCE_GUIDE.md`）
5. 余裕があれば: 雨の景色のプロトタイプ用にワールドのテンプレート化を検討

## ユーザーにお願いすること（すべてブラウザで完結）

1. **詳細なキャラ設定を送る**（後日。`docs/REFERENCE_GUIDE.md` 1 章の「先に決めておくこと」も目を通してください）
2. **ChatGPT でキャラ画像を作る**（`docs/REFERENCE_GUIDE.md` 2〜3 章のプロンプト）。できた PNG は GitHub の Add file → Upload files で `docs/reference/character/` に置く
3. **決めてほしいこと**
   - ブラウザで歩いてみた感想（速い / 遅い、カメラが近い / 遠い、酔う / 酔わない、視野角）
   - コートの長さ: 膝上 or 前が割れた長いコート（脚が見える必要がある。理由はガイド 1 章）
   - 一人称切替のキーは V でよい？

## 自宅PCでやること（ソフト導入が要るもの）

- Godot 4.7.2 をインストールし、`game/project.godot` を開いて実機で歩く。実行ファイルのパスを CLAUDE.md の「環境メモ」に書く
- Blender 4.x をインストールし、パスを CLAUDE.md に書く（フェーズ2 で bpy スクリプトを動かすため）
- Git for Windows（Git Bash）が入っていれば、SessionStart フック（`.claude/hooks/session-start.sh`）はそのまま動く

## ファイルの場所（今回追加したもの）

| 場所 | 内容 |
|---|---|
| `game/scripts/tuning.gd` | 操作感の数値（すべてここ） |
| `game/scenes/player/` | 仮キャラ（player.gd）とカメラ（camera_rig.gd） |
| `game/scenes/worlds/gray/` | 灰色の世界（地面・箱・フォグ） |
| `game/scenes/ui/` | 操作案内の HUD と F1 調整パネル |
| `game/shaders/grid_ground.gdshader` | 地面のグリッド |
| `game/tools/` | headless テスト・スクリーンショット用のシーン |
| `game/export_presets.cfg` | Web 書き出し設定（スレッド無効） |
| `tools/cloud-setup.sh` | クラウド環境に Godot / Blender を導入 |
| `tools/export-web.sh` / `tools/screenshot.sh` | Web 書き出し / スクリーンショット |
| `.github/workflows/deploy-pages.yml` | main への push で Pages に自動配置 |
| `.claude/settings.json` / `.claude/hooks/session-start.sh` | セッション開始時の git pull |
