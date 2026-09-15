# HANDOFF.md — 引き継ぎメモ

最終更新: 2026-09-15（クラウドセッション）

## ブラウザで確認できる URL

- **https://axelrodichthys-blip.github.io/uchi-games/**
  - ※ まだ開けません。下の「ユーザーにお願いすること」の 1〜2 を済ませると、数分後に開けるようになります
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

- **GitHub Pages はまだ有効化されていない**（リポジトリ設定はユーザーしか変えられない）
- **このリポジトリは private**。GitHub Pages を private リポジトリで使うには有料プラン（Pro）が必要。無料で使うならリポジトリを public にする必要がある
- 今回の作業はブランチ `claude/game-phase-0-to-1-69bbxr` に push した（セッションの設定で main への直接 push が禁止されていたため）。main に取り込まないと Pages の自動配置は動かない
- Web ビルドの日本語フォント: VL Gothic を同梱した（同梱前はブラウザで日本語が□になっていた）
- 操作感の数値はすべて初期値のまま（ユーザーの感想待ち）
- Windows 側の Godot / Blender のパスは未設定

## 次にやること

1. ユーザーがブラウザで歩き、操作感の感想をもらう（速さ・カメラ距離・感度・視野角）。F1 パネルで見つけた値を `game/scripts/tuning.gd` の初期値に反映する
2. 「歩く気持ちよさ」の初手: 足音、歩行時のカメラの微かな揺れ、加減速の味付け
3. フェーズ2 の準備: ChatGPT でキャラ画像（Tポーズ・白背景・正面 / 側面 / 背面）を作ってもらう手順の提示
4. 余裕があれば: タイトル画面なしでいきなり歩ける今の形を維持しつつ、雨の景色のプロトタイプ用にワールドのテンプレート化を検討

## ユーザーにお願いすること（すべてブラウザで完結）

1. **リポジトリを public にする（無料プランの場合）**
   Settings → General → 一番下の Danger Zone → Change repository visibility → Public
   （private のままにしたい場合は GitHub Pro が必要。その場合は教えてください。代わりに itch.io へ直接アップロードする案もあります）
2. **GitHub Pages を有効化する**
   Settings → Pages → Build and deployment → Source を **「GitHub Actions」** にする（保存ボタンはなく、選ぶだけ）
3. **ブランチを main に取り込む**
   https://github.com/axelrodichthys-blip/uchi-games/compare/main...claude/game-phase-0-to-1-69bbxr を開く → Create pull request → Merge pull request
   （または次のセッションで「main に push して」と言ってもらえれば Claude がやります）
   → main に入ると Actions の「Web 書き出し → GitHub Pages」が走り、2〜3分で上の URL が開けるようになります。Actions タブで進み具合を見られます
4. **決めてほしいこと**
   - ブラウザで歩いてみた感想（速い / 遅い、カメラが近い / 遠い、酔う / 酔わない、視野角）
   - ジャンプは入れる？（今は無し）
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
